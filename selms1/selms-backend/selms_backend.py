"""
selms_backend.py

Flask REST API for SELMS — the "API Gateway" layer from the FYP's system
architecture (Figure 3.2). Covers login, full employee management (create,
universal search, view, edit, delete), and an Excel export of the current
filtered employee list — all gated to HR accounts.

Pairs with:
  - scripts/seed_account.py -> creates the first HR or IT account (run once each)
  - scripts/reset_hr_password.py -> resets it if forgotten
  - lib/screens/selms_login_screen.dart   -> POSTs to /api/auth/login
  - lib/screens/add_employee_screen.dart / review_employee_screen.dart
    -> POSTs to /api/employees
  - lib/screens/employee_directory_screen.dart -> GET /api/employees,
    GET /api/employees/export
  - lib/screens/employee_view_screen.dart      -> GET/DELETE /api/employees/<id>
  - lib/screens/employee_edit_screen.dart      -> PUT /api/employees/<id>

Run:
    pip install flask flask-cors pymongo bcrypt pyjwt openpyxl --break-system-packages
    export MONGO_URI="mongodb://localhost:27017"
    export JWT_SECRET="change-this-in-production"
    python selms_backend.py
"""

import os
import re
import secrets
import smtplib
import ssl
import urllib.request
import uuid
import json as _json
from email.message import EmailMessage
from datetime import datetime, timedelta, timezone
from functools import wraps
from io import BytesIO

import bcrypt
import jwt
from bson import ObjectId
from flask import Flask, request, jsonify, g, send_file, send_from_directory
from flask_cors import CORS
from pymongo import MongoClient
from openpyxl import Workbook
from werkzeug.utils import secure_filename

MONGO_URI = os.environ.get("MONGO_URI", "mongodb://localhost:27017")
DB_NAME = os.environ.get("SELMS_DB", "selms")
JWT_SECRET = os.environ.get("JWT_SECRET", "dev-secret-change-me")
JWT_EXPIRY_HOURS = 8
VALID_ROLES = {"hr", "it", "employee"}

# --- Profile photo storage ---
# Option A: plain files on the backend's own disk, served back out via
# GET /uploads/<filename>. Fine for local/single-server deployments; if this
# ever moves to a host with an ephemeral filesystem, point this at a
# persistent volume (or swap for object storage) instead.
UPLOAD_FOLDER = os.environ.get("SELMS_UPLOAD_FOLDER", os.path.join(os.path.dirname(__file__), "uploads"))
ALLOWED_PHOTO_EXTENSIONS = {"jpg", "jpeg", "png"}
MAX_PHOTO_BYTES = 5 * 1024 * 1024  # 5MB, matches the "up to 5MB" hint in the app
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

# --- Email (SMTP) ---
# Free option: a Gmail account with 2FA on + an "App Password" generated for
# this app. No Microsoft tenant, no paid service — just an existing mailbox.
SMTP_HOST = os.environ.get("SMTP_HOST", "smtp.gmail.com")
SMTP_PORT = int(os.environ.get("SMTP_PORT", "587"))
SMTP_USER = os.environ.get("SMTP_USER", "")
SMTP_PASSWORD = os.environ.get("SMTP_PASSWORD", "")
SMTP_FROM_NAME = os.environ.get("SMTP_FROM_NAME", "SELMS HR")

# --- AI email drafting (optional) ---
# If set, draft requests call Anthropic's Messages API to write the welcome
# email. If not set, a fixed template is used instead — either way, HR
# reviews and can edit the draft before it sends (see /api/onboarding/*).
ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
ANTHROPIC_MODEL = os.environ.get("ANTHROPIC_MODEL", "claude-sonnet-4-6")

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = MAX_PHOTO_BYTES + (1 * 1024 * 1024)  # a little headroom over the photo cap
CORS(app)  # needed since the Flutter web app runs on a different origin

client = MongoClient(MONGO_URI)
db = client[DB_NAME]
users = db["users"]
onboarding_flows = db["onboarding_flows"]
offboarding_flows = db["offboarding_flows"]
equipment = db["equipment"]
bookings = db["bookings"]


# ---------- Email ----------

def send_email(to_email: str, subject: str, html_body: str) -> None:
    """Sends one email over SMTP. Raises on failure — caller decides whether
    that should be reported back (manual resend) or just logged (automatic
    onboarding chain, where a slow/flaky mail server shouldn't block account
    creation)."""
    if not SMTP_USER or not SMTP_PASSWORD:
        raise RuntimeError("SMTP_USER / SMTP_PASSWORD not configured.")

    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = f"{SMTP_FROM_NAME} <{SMTP_USER}>"
    msg["To"] = to_email
    msg.set_content("This email requires an HTML-capable client to view.")
    msg.add_alternative(html_body, subtype="html")

    context = ssl.create_default_context()
    with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
        server.starttls(context=context)
        server.login(SMTP_USER, SMTP_PASSWORD)
        server.send_message(msg)


def _fallback_welcome_email(full_name: str, job_title: str, department: str, work_email: str) -> dict:
    """Used when ANTHROPIC_API_KEY isn't set, or the API call fails — a
    plain, always-available draft so onboarding never gets stuck for lack
    of an AI key."""
    return {
        "subject": f"Welcome to the team, {full_name}!",
        "body": (
            f"Hi {full_name},\n\n"
            f"We're delighted to welcome you as our new {job_title} in the "
            f"{department} team. Your work email, {work_email}, is now ready — "
            f"HR will be in touch shortly to confirm your orientation session.\n\n"
            f"Looking forward to having you on board!\n\n"
            f"Warm regards,\nHR Team"
        ),
    }


def draft_welcome_email(full_name: str, job_title: str, department: str, work_email: str,
                         instruction: str = "") -> dict:
    """Returns {"subject": ..., "body": ...}. Tries the Anthropic API first
    if configured; falls back to a fixed template on any failure so this
    never blocks HR from proceeding."""
    if not ANTHROPIC_API_KEY:
        return _fallback_welcome_email(full_name, job_title, department, work_email)

    prompt = (
        f"Write a short, warm welcome email for a new employee joining a company. "
        f"Name: {full_name}. Job title: {job_title}. Department: {department}. "
        f"Their new work email is {work_email}. Mention that HR will follow up "
        f"about orientation scheduling. Keep it under 120 words, friendly but "
        f"professional, no placeholders like [Company Name]. "
        + (f"Additional instruction: {instruction}. " if instruction else "")
        + 'Respond ONLY as JSON: {"subject": "...", "body": "..."} — no other text.'
    )

    try:
        req = urllib.request.Request(
            "https://api.anthropic.com/v1/messages",
            data=_json.dumps({
                "model": ANTHROPIC_MODEL,
                "max_tokens": 400,
                "messages": [{"role": "user", "content": prompt}],
            }).encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "x-api-key": ANTHROPIC_API_KEY,
                "anthropic-version": "2023-06-01",
            },
        )
        with urllib.request.urlopen(req, timeout=15) as res:
            data = _json.loads(res.read())
        text = data["content"][0]["text"].strip()
        # Model may wrap JSON in ```json fences despite instructions — strip them.
        text = text.removeprefix("```json").removeprefix("```").removesuffix("```").strip()
        parsed = _json.loads(text)
        return {"subject": parsed["subject"], "body": parsed["body"]}
    except Exception as exc:  # noqa: BLE001 — any failure just falls back
        print(f"[AI draft] falling back to template: {exc}")
        return _fallback_welcome_email(full_name, job_title, department, work_email)


def _welcome_email_html(body_text: str, confirm_url: str) -> str:
    """Wraps HR's (possibly AI-drafted, possibly edited) plain-text body in
    HTML, with the confirmation link that flips onboarding_status.email_confirmed
    when the employee clicks it."""
    paragraphs = "".join(f"<p>{line}</p>" for line in body_text.split("\n") if line.strip())
    return f"""
    <div style="font-family:sans-serif;color:#14161b">
      {paragraphs}
      <p style="margin-top:20px">
        <a href="{confirm_url}" style="background:#14161b;color:#fff;padding:10px 18px;
           border-radius:6px;text-decoration:none;display:inline-block">
          Confirm you've received this
        </a>
      </p>
    </div>
    """


# ---------- Auth ----------

@app.post("/api/auth/login")
def login():
    body = request.get_json(silent=True) or {}
    role = (body.get("role") or "").strip().lower()
    email = (body.get("email") or "").strip().lower()
    password = body.get("password") or ""

    if role not in VALID_ROLES:
        return jsonify({"message": "Unrecognised role."}), 400
    if not email or not password:
        return jsonify({"message": "Email and password are required."}), 400

    user = users.find_one({"email": email})
    invalid = jsonify({"message": "Invalid email, password, or role."})

    if not user:
        return invalid, 401
    if user.get("role") != role:
        return invalid, 401
    if not bcrypt.checkpw(password.encode("utf-8"), user["password_hash"]):
        return invalid, 401

    token = jwt.encode(
        {
            "sub": str(user["_id"]),
            "email": user["email"],
            "role": user["role"],
            "full_name": user.get("full_name"),
            "iat": datetime.now(timezone.utc),
            "exp": datetime.now(timezone.utc) + timedelta(hours=JWT_EXPIRY_HOURS),
        },
        JWT_SECRET,
        algorithm="HS256",
    )

    return jsonify({
        "token": token,
        "role": user["role"],
        "full_name": user.get("full_name"),
    }), 200


@app.get("/api/health")
def health():
    return jsonify({"status": "ok"}), 200


def _extract_token():
    """Accept the JWT from the Authorization header (normal API calls) or a
    ?token= query param (needed for the Excel export link, since a plain
    browser download/navigation can't attach custom headers)."""
    auth_header = request.headers.get("Authorization", "")
    if auth_header.startswith("Bearer "):
        return auth_header.removeprefix("Bearer ").strip()
    return request.args.get("token")


def require_hr(fn):
    """Only an HR admin's JWT may call the decorated route."""
    @wraps(fn)
    def wrapper(*args, **kwargs):
        token = _extract_token()
        if not token:
            return jsonify({"message": "Missing or invalid Authorization header."}), 401

        try:
            payload = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
        except jwt.ExpiredSignatureError:
            return jsonify({"message": "Session expired. Please log in again."}), 401
        except jwt.InvalidTokenError:
            return jsonify({"message": "Invalid session token."}), 401

        if payload.get("role") != "hr":
            return jsonify({"message": "Only HR admins can do this."}), 403

        g.current_user = payload
        return fn(*args, **kwargs)

    return wrapper


def require_it(fn):
    """Only an IT staff JWT may call the decorated route."""
    @wraps(fn)
    def wrapper(*args, **kwargs):
        token = _extract_token()
        if not token:
            return jsonify({"message": "Missing or invalid Authorization header."}), 401

        try:
            payload = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
        except jwt.ExpiredSignatureError:
            return jsonify({"message": "Session expired. Please log in again."}), 401
        except jwt.InvalidTokenError:
            return jsonify({"message": "Invalid session token."}), 401

        if payload.get("role") != "it":
            return jsonify({"message": "Only IT staff can do this."}), 403

        g.current_user = payload
        return fn(*args, **kwargs)

    return wrapper


def require_hr_or_it(fn):
    """Either an HR admin's or IT staff's JWT may call the decorated route
    — used for things both roles legitimately need, like looking up
    employees to assign equipment to, without opening the full HR-only
    employee list."""
    @wraps(fn)
    def wrapper(*args, **kwargs):
        token = _extract_token()
        if not token:
            return jsonify({"message": "Missing or invalid Authorization header."}), 401

        try:
            payload = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
        except jwt.ExpiredSignatureError:
            return jsonify({"message": "Session expired. Please log in again."}), 401
        except jwt.InvalidTokenError:
            return jsonify({"message": "Invalid session token."}), 401

        if payload.get("role") not in ("hr", "it"):
            return jsonify({"message": "Not authorized."}), 403

        g.current_user = payload
        return fn(*args, **kwargs)

    return wrapper


def require_employee(fn):
    """Only an employee's own JWT may call the decorated route. Unlike
    require_hr/require_it, every route below acts on "me" rather than an
    employee_id taken from the URL, so this also loads the caller's own
    document onto g.current_employee — one employee's token can never
    read or sign for another employee."""
    @wraps(fn)
    def wrapper(*args, **kwargs):
        token = _extract_token()
        if not token:
            return jsonify({"message": "Missing or invalid Authorization header."}), 401

        try:
            payload = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
        except jwt.ExpiredSignatureError:
            return jsonify({"message": "Session expired. Please log in again."}), 401
        except jwt.InvalidTokenError:
            return jsonify({"message": "Invalid session token."}), 401

        if payload.get("role") != "employee":
            return jsonify({"message": "Only employees can do this."}), 403

        doc = users.find_one({"_id": ObjectId(payload["sub"]), "role": "employee"})
        if not doc:
            return jsonify({"message": "Invalid session token."}), 401

        g.current_user = payload
        g.current_employee = doc
        return fn(*args, **kwargs)

    return wrapper


# ---------- Equipment (IT) ----------

DEFAULT_EQUIPMENT_TYPES = ["Laptop", "Phone", "Headphone", "Monitor", "Mouse", "Keyboard"]


@app.post("/api/equipment")
@require_it
def create_equipment():
    body = request.get_json(silent=True) or {}
    name = (body.get("name") or "").strip()
    type_ = (body.get("type") or "").strip()
    serial_number = (body.get("serial_number") or "").strip()

    if not name or not type_ or not serial_number:
        return jsonify({"message": "Name, type, and serial number are all required."}), 400

    if equipment.find_one({"serial_number": serial_number}):
        return jsonify({"message": "An item with this serial number already exists."}), 409

    doc = {
        # Identification (specs merged in here — no separate section)
        "name": name,
        "type": type_,
        "brand": (body.get("brand") or "").strip(),
        "model": (body.get("model") or "").strip(),
        "serial_number": serial_number,
        "asset_tag": (body.get("asset_tag") or "").strip(),
        "color_marks": (body.get("color_marks") or "").strip(),
        "ram": (body.get("ram") or "").strip(),
        "storage": (body.get("storage") or "").strip(),
        "software_licenses": (body.get("software_licenses") or "").strip(),
        # Condition & status
        "condition": body.get("condition") or "New",
        "status": "available",  # available | assigned | returned | under_repair | retired | lost
        "assigned_to_employee_id": None,
        "accessories_included": (body.get("accessories_included") or "").strip(),
        # Purchase & warranty
        "purchase_date": body.get("purchase_date"),
        "purchase_price": body.get("purchase_price"),
        "vendor": (body.get("vendor") or "").strip(),
        "warranty_expiry": body.get("warranty_expiry"),
        # Notes & photo
        "notes": (body.get("notes") or "").strip(),
        "photo_url": None,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    result = equipment.insert_one(doc)
    doc["_id"] = str(result.inserted_id)
    return jsonify(doc), 201


@app.get("/api/equipment/<equipment_id>")
@require_it
def get_equipment(equipment_id):
    try:
        doc = equipment.find_one({"_id": ObjectId(equipment_id)})
    except Exception:
        doc = None
    if not doc:
        return jsonify({"message": "Equipment not found."}), 404
    doc["_id"] = str(doc["_id"])
    return jsonify(doc), 200


@app.put("/api/equipment/<equipment_id>")
@require_it
def update_equipment(equipment_id):
    try:
        existing = equipment.find_one({"_id": ObjectId(equipment_id)})
    except Exception:
        existing = None
    if not existing:
        return jsonify({"message": "Equipment not found."}), 404

    body = request.get_json(silent=True) or {}
    updatable = {
        "name", "type", "brand", "model", "serial_number", "asset_tag",
        "ram", "storage", "color_marks", "software_licenses",
        "condition", "status", "accessories_included",
        "purchase_date", "purchase_price", "vendor", "warranty_expiry", "notes",
    }
    updates = {k: v for k, v in body.items() if k in updatable}

    if "serial_number" in updates:
        dupe = equipment.find_one({"serial_number": updates["serial_number"], "_id": {"$ne": ObjectId(equipment_id)}})
        if dupe:
            return jsonify({"message": "An item with this serial number already exists."}), 409

    if updates:
        equipment.update_one({"_id": ObjectId(equipment_id)}, {"$set": updates})

    doc = equipment.find_one({"_id": ObjectId(equipment_id)})
    doc["_id"] = str(doc["_id"])
    return jsonify(doc), 200


@app.post("/api/equipment/assign")
@require_it
def assign_equipment():
    """Assigns one or more equipment items to one employee in a single
    call — the multi-item "hand over a full kit" case and the single-item
    case both go through here, just with a list of 1 or many IDs.

    Stores both the employee's ID (for the real relational link) and their
    name (denormalized onto the equipment record) so a future equipment
    search by employee name doesn't need a slow cross-collection join —
    see the planning notes this was built from."""
    body = request.get_json(silent=True) or {}
    employee_id = (body.get("employee_id") or "").strip()
    equipment_ids = body.get("equipment_ids") or []
    notes = (body.get("notes") or "").strip()

    if not employee_id or not isinstance(equipment_ids, list) or not equipment_ids:
        return jsonify({"message": "employee_id and a non-empty equipment_ids list are required."}), 400

    employee = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not employee:
        return jsonify({"message": "Employee not found."}), 404

    try:
        object_ids = [ObjectId(eid) for eid in equipment_ids]
    except Exception:
        return jsonify({"message": "One or more equipment IDs were invalid."}), 400

    result = equipment.update_many(
        {"_id": {"$in": object_ids}},
        {"$set": {
            "status": "assigned",
            "assigned_to_employee_id": employee_id,
            "assigned_to_employee_name": employee.get("full_name"),
            "assigned_to_employee_department": employee.get("department"),
            "assigned_to_employee_photo_url": employee.get("profile_image_url"),
            "assigned_date": datetime.now(timezone.utc).isoformat(),
            "assignment_notes": notes,
        }},
    )
    return jsonify({"message": f"Assigned {result.modified_count} item(s) to {employee.get('full_name')}."}), 200


@app.post("/api/equipment/<equipment_id>/return")
@require_it
def return_equipment(equipment_id):
    """Reverses an assignment — clears who has it and, based on the
    reported condition, either frees it back up (Good) or routes it to
    Under repair (Damaged) instead of straight back to Available."""
    try:
        doc = equipment.find_one({"_id": ObjectId(equipment_id)})
    except Exception:
        doc = None
    if not doc:
        return jsonify({"message": "Equipment not found."}), 404

    body = request.get_json(silent=True) or {}
    condition_on_return = body.get("condition")
    return_notes = (body.get("notes") or "").strip()
    new_status = "under_repair" if condition_on_return == "Damaged" else "available"

    updates = {
        "status": new_status,
        "assigned_to_employee_id": None,
        "assigned_to_employee_name": None,
        "assigned_to_employee_department": None,
        "assigned_to_employee_photo_url": None,
        "assigned_date": None,
        "assignment_notes": None,
        # Kept even after the assignment itself is cleared — a lightweight
        # record of what happened at the most recent retrieval.
        "last_return_notes": return_notes or None,
        "last_returned_date": datetime.now(timezone.utc).isoformat(),
    }
    if condition_on_return:
        updates["condition"] = condition_on_return

    equipment.update_one({"_id": ObjectId(equipment_id)}, {"$set": updates})
    doc = equipment.find_one({"_id": ObjectId(equipment_id)})
    doc["_id"] = str(doc["_id"])
    return jsonify(doc), 200


@app.post("/api/equipment/<equipment_id>/photo")
@require_it
def upload_equipment_photo(equipment_id):
    """Same pattern as the employee profile photo endpoint — saves to the
    shared UPLOAD_FOLDER and records the public path on the record."""
    try:
        doc = equipment.find_one({"_id": ObjectId(equipment_id)})
    except Exception:
        doc = None
    if not doc:
        return jsonify({"message": "Equipment not found."}), 404

    file = request.files.get("photo")
    if file is None or file.filename == "":
        return jsonify({"message": "No photo file was sent."}), 400

    ext = file.filename.rsplit(".", 1)[-1].lower() if "." in file.filename else ""
    if ext not in ALLOWED_PHOTO_EXTENSIONS:
        return jsonify({"message": "Photo must be a JPG or PNG file."}), 400

    filename = secure_filename(f"equipment-{equipment_id}.{ext}")
    file.save(os.path.join(UPLOAD_FOLDER, filename))

    photo_url = f"/uploads/{filename}"
    equipment.update_one({"_id": ObjectId(equipment_id)}, {"$set": {"photo_url": photo_url}})

    return jsonify({"message": "Photo uploaded.", "photo_url": photo_url}), 200


EQUIPMENT_SEARCHABLE_FIELDS = ["name", "type", "brand", "model", "serial_number", "asset_tag", "assigned_to_employee_name"]

EQUIPMENT_EXPORT_COLUMNS = [
    ("name", "Name"),
    ("type", "Type"),
    ("brand", "Brand"),
    ("model", "Model"),
    ("serial_number", "Serial Number"),
    ("asset_tag", "Asset Tag"),
    ("ram", "RAM"),
    ("storage", "Storage"),
    ("color_marks", "Color / Marks"),
    ("software_licenses", "Software / Licenses"),
    ("condition", "Condition"),
    ("status", "Status"),
    ("assigned_to_employee_id", "Assigned Employee ID"),
    ("assigned_to_employee_name", "Assigned Employee Name"),
    ("accessories_included", "Accessories Included"),
    ("purchase_date", "Purchase Date"),
    ("purchase_price", "Purchase Price (RM)"),
    ("vendor", "Vendor"),
    ("warranty_expiry", "Warranty Expiry"),
    ("notes", "Notes"),
]


def _build_equipment_query(args):
    """Shared by GET /api/equipment and GET /api/equipment/export so an
    exported file always matches whatever's currently filtered on screen."""
    query = {}

    q = (args.get("q") or "").strip()
    if q:
        pattern = re.escape(q)
        query["$or"] = [{f: {"$regex": pattern, "$options": "i"}} for f in EQUIPMENT_SEARCHABLE_FIELDS]

    type_ = args.get("type")
    if type_:
        query["type"] = type_

    status = args.get("status")
    if status:
        query["status"] = status

    condition = args.get("condition")
    if condition:
        query["condition"] = condition

    return query


@app.get("/api/equipment")
@require_it
def list_equipment():
    query = _build_equipment_query(request.args)
    items = []
    for doc in equipment.find(query).sort("created_at", -1):
        doc["_id"] = str(doc["_id"])
        items.append(doc)
    return jsonify({"items": items}), 200


@app.get("/api/equipment/export")
@require_it
def export_equipment():
    """Exports exactly what's currently filtered/searched on screen — same
    query params as GET /api/equipment."""
    query = _build_equipment_query(request.args)
    docs = list(equipment.find(query).sort("created_at", -1))

    wb = Workbook()
    ws = wb.active
    ws.title = "Equipment"
    ws.append([label for _, label in EQUIPMENT_EXPORT_COLUMNS])

    for d in docs:
        row = [d.get(key) for key, _ in EQUIPMENT_EXPORT_COLUMNS]
        ws.append(row)

    for i, (_, label) in enumerate(EQUIPMENT_EXPORT_COLUMNS, start=1):
        ws.column_dimensions[ws.cell(row=1, column=i).column_letter].width = max(14, len(label) + 2)

    buffer = BytesIO()
    wb.save(buffer)
    buffer.seek(0)

    return send_file(
        buffer,
        mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        as_attachment=True,
        download_name="selms_equipment.xlsx",
    )


@app.get("/api/equipment/types")
@require_it
def list_equipment_types():
    """Defaults plus any custom type names already in use, so a type someone
    added once shows up for everybody afterwards — not just that session."""
    custom = equipment.distinct("type")
    seen = list(DEFAULT_EQUIPMENT_TYPES)
    for t in custom:
        if t not in seen:
            seen.append(t)
    return jsonify({"types": seen}), 200


@app.get("/api/equipment/summary")
@require_it
def equipment_summary():
    total = equipment.count_documents({})
    available = equipment.count_documents({"status": "available"})
    assigned = equipment.count_documents({"status": "assigned"})
    returned = equipment.count_documents({"status": "returned"})
    return jsonify({
        "total": total,
        "available": available,
        "assigned": assigned,
        "returned": returned,
    }), 200



REQUIRED_EMPLOYEE_FIELDS = [
    "full_name", "gender", "date_of_birth", "nationality", "ic_passport_no",
    "marital_status", "address_line", "postcode", "state", "personal_email",
    "mobile_number", "emergency_contact_name", "emergency_contact_number",
    "emergency_contact_relationship",
    "job_title", "department", "line_manager", "hire_date",
    "employment_status", "work_location_type", "base_salary",
    "equipment_needed", "work_email", "temp_password",
]

# Fields the universal search box matches against. Filters (department/
# employment status/work location type) are separate and narrower.
SEARCHABLE_FIELDS = [
    "full_name", "employee_id", "department", "job_title",
    "work_location_type", "employment_status", "personal_email",
    "email", "mobile_number", "line_manager", "ic_passport_no",
    "postcode", "state",
]

EXPORT_COLUMNS = [
    ("employee_id", "Employee ID"),
    ("full_name", "Name"),
    ("gender", "Gender"),
    ("date_of_birth", "Date of Birth"),
    ("nationality", "Nationality"),
    ("ic_passport_no", "IC / Passport No."),
    ("marital_status", "Marital Status"),
    ("address_line", "Address"),
    ("postcode", "Postcode"),
    ("state", "State"),
    ("personal_email", "Personal Email"),
    ("mobile_number", "Mobile Number"),
    ("emergency_contact_name", "Emergency Contact Name"),
    ("emergency_contact_number", "Emergency Contact No."),
    ("emergency_contact_relationship", "Emergency Contact Relationship"),
    ("job_title", "Job Title"),
    ("department", "Department"),
    ("line_manager", "Line Manager"),
    ("hire_date", "Hire Date"),
    ("confirmation_date", "Confirmation Date"),
    ("employment_status", "Employment Status"),
    ("work_location_type", "Work Location Type"),
    ("base_salary", "Base Salary (RM)"),
    ("equipment_needed", "Equipment"),
    ("remarks", "Remarks"),
    ("work_email", "Work Email"),
    ("onboarding_stage", "Onboarding Stage"),
    ("profile_image_url", "Profile Photo URL"),
]


def _next_employee_id():
    count = users.count_documents({"role": "employee"})
    return f"EMP-{count + 1:03d}"


def _employee_public_view(doc):
    out = dict(doc)
    out.pop("_id", None)
    out.pop("password_hash", None)
    return out


def _build_employee_query(args):
    """Shared by GET /api/employees and GET /api/employees/export so an
    exported file always matches whatever's currently on screen."""
    query = {"role": "employee"}

    q = (args.get("q") or "").strip()
    if q:
        pattern = re.escape(q)
        query["$or"] = [{f: {"$regex": pattern, "$options": "i"}} for f in SEARCHABLE_FIELDS]

    department = args.get("department")
    if department:
        query["department"] = department

    employment_status = args.get("employment_status")
    if employment_status:
        query["employment_status"] = employment_status

    work_location_type = args.get("work_location_type")
    if work_location_type:
        query["work_location_type"] = work_location_type

    return query


@app.post("/api/employees")
@require_hr
def create_employee():
    body = request.get_json(silent=True) or {}

    missing = [f for f in REQUIRED_EMPLOYEE_FIELDS if body.get(f) in (None, "", [])]
    if missing:
        return jsonify({"message": f"Missing required fields: {', '.join(missing)}"}), 400

    work_email = body["work_email"].strip().lower()
    if users.find_one({"email": work_email}):
        return jsonify({"message": "An account with this work email already exists."}), 409

    employee_id = (body.get("employee_id") or "").strip()
    if not employee_id or employee_id == "(auto-generated)" or users.find_one({"employee_id": employee_id}):
        employee_id = _next_employee_id()

    password_hash = bcrypt.hashpw(body["temp_password"].encode("utf-8"), bcrypt.gensalt())

    users.insert_one({
        "employee_id": employee_id,
        "role": "employee",
        "email": work_email,
        "work_email": work_email,
        "password_hash": password_hash,
        "full_name": body["full_name"].strip(),
        "gender": body["gender"],
        "date_of_birth": body["date_of_birth"],
        "nationality": body["nationality"].strip(),
        "ic_passport_no": body["ic_passport_no"].strip(),
        "marital_status": body["marital_status"],
        "address_line": body["address_line"].strip(),
        "postcode": body["postcode"].strip(),
        "state": body["state"],
        "personal_email": body["personal_email"].strip().lower(),
        "mobile_number": body["mobile_number"].strip(),
        "emergency_contact_name": body["emergency_contact_name"].strip(),
        "emergency_contact_number": body["emergency_contact_number"].strip(),
        "emergency_contact_relationship": body["emergency_contact_relationship"],
        "job_title": body["job_title"].strip(),
        "department": body["department"],
        "line_manager": body["line_manager"].strip(),
        "hire_date": body["hire_date"],
        "confirmation_date": body.get("confirmation_date"),
        "employment_status": body["employment_status"],
        "work_location_type": body["work_location_type"],
        "base_salary": body["base_salary"],
        "equipment_needed": body["equipment_needed"],
        "remarks": body.get("remarks", ""),
        # Set by POST /api/employees/<id>/photo after this record exists —
        # the frontend uploads the photo as a follow-up call since the
        # employee_id isn't known until this insert completes.
        "profile_image_url": None,
        # No onboarding_stage set here anymore — onboarding is a separate,
        # HR-triggered action from the Onboarding tab, not automatic on
        # registration. See the onboarding_status object set by
        # POST /api/onboarding/<id>/start.
        "created_by": g.current_user["email"],
        "created_at": datetime.now(timezone.utc).isoformat(),
    })

    return jsonify({"message": "Employee registered.", "employee_id": employee_id}), 201


@app.get("/api/employees")
@require_hr
def list_employees():
    query = _build_employee_query(request.args)
    docs = list(users.find(query).sort("created_at", -1))
    return jsonify({"employees": [_employee_public_view(d) for d in docs]}), 200


@app.get("/api/employees/lookup")
@require_hr_or_it
def lookup_employees():
    """Lightweight employee search for the equipment-assign picker — just
    enough to find and identify someone (name, ID, department), not the
    full HR record that GET /api/employees returns."""
    q = (request.args.get("q") or "").strip()
    query = {"role": "employee"}
    if q:
        pattern = re.escape(q)
        query["$or"] = [{"full_name": {"$regex": pattern, "$options": "i"}},
                         {"employee_id": {"$regex": pattern, "$options": "i"}}]
    docs = list(users.find(query, {"employee_id": 1, "full_name": 1, "department": 1}).sort("full_name", 1).limit(50))
    results = [{"employee_id": d.get("employee_id"), "full_name": d.get("full_name"), "department": d.get("department")}
               for d in docs]
    return jsonify({"employees": results}), 200


@app.get("/api/employees/export")
@require_hr
def export_employees():
    """Exports exactly what's currently filtered/searched on screen — same
    query params as GET /api/employees."""
    query = _build_employee_query(request.args)
    docs = list(users.find(query).sort("created_at", -1))

    wb = Workbook()
    ws = wb.active
    ws.title = "Employees"
    ws.append([label for _, label in EXPORT_COLUMNS])

    for d in docs:
        row = []
        for key, _ in EXPORT_COLUMNS:
            value = d.get(key)
            if key == "equipment_needed" and isinstance(value, list):
                value = ", ".join(value)
            row.append(value)
        ws.append(row)

    for i, (_, label) in enumerate(EXPORT_COLUMNS, start=1):
        ws.column_dimensions[ws.cell(row=1, column=i).column_letter].width = max(14, len(label) + 2)

    buffer = BytesIO()
    wb.save(buffer)
    buffer.seek(0)

    return send_file(
        buffer,
        mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        as_attachment=True,
        download_name="selms_employees.xlsx",
    )


@app.post("/api/employees/<employee_id>/send-welcome-email")
@require_hr
def resend_welcome_email(employee_id):
    """Manual trigger from View Employee. Unlike the automatic one at
    creation, this runs synchronously — HR clicked a button and should know
    right away whether it actually sent."""
    doc = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not doc:
        return jsonify({"message": "Employee not found."}), 404

    try:
        send_email(
            to_email=doc["personal_email"],
            subject=f"Welcome to the team, {doc['full_name']}!",
            html_body=_welcome_email_html(
                doc["full_name"], doc["work_email"], doc["department"], doc["job_title"],
            ),
        )
    except Exception as exc:
        return jsonify({"message": f"Could not send email: {exc}"}), 502

    return jsonify({"message": f"Welcome email sent to {doc['personal_email']}."}), 200


@app.post("/api/employees/<employee_id>/photo")
@require_hr
def upload_employee_photo(employee_id):
    """Saves the uploaded profile photo to UPLOAD_FOLDER and records its
    public path on the employee document. Multipart, not JSON — called
    separately from create/update since the file itself isn't part of the
    regular employee payload."""
    doc = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not doc:
        return jsonify({"message": "Employee not found."}), 404

    file = request.files.get("photo")
    if file is None or file.filename == "":
        return jsonify({"message": "No photo file was sent."}), 400

    ext = file.filename.rsplit(".", 1)[-1].lower() if "." in file.filename else ""
    if ext not in ALLOWED_PHOTO_EXTENSIONS:
        return jsonify({"message": "Photo must be a JPG or PNG file."}), 400

    filename = secure_filename(f"{employee_id}.{ext}")
    file.save(os.path.join(UPLOAD_FOLDER, filename))

    profile_image_url = f"/uploads/{filename}"
    users.update_one({"employee_id": employee_id}, {"$set": {"profile_image_url": profile_image_url}})

    return jsonify({"message": "Photo uploaded.", "profile_image_url": profile_image_url}), 200


@app.get("/uploads/<path:filename>")
def serve_upload(filename):
    """Public by design — profile photos are shown in the app's directory
    grid and don't contain sensitive data on their own. If that changes,
    gate this behind @require_hr like everything else."""
    return send_from_directory(UPLOAD_FOLDER, filename)


@app.get("/api/employees/<employee_id>")
@require_hr
def get_employee(employee_id):
    doc = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not doc:
        return jsonify({"message": "Employee not found."}), 404
    return jsonify(_employee_public_view(doc)), 200


@app.put("/api/employees/<employee_id>")
@require_hr
def update_employee(employee_id):
    doc = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not doc:
        return jsonify({"message": "Employee not found."}), 404

    body = request.get_json(silent=True) or {}
    reset_password = body.pop("reset_password", False)

    updatable = {
        "full_name", "gender", "date_of_birth", "nationality", "ic_passport_no",
        "marital_status", "address_line", "postcode", "state", "personal_email",
        "mobile_number", "emergency_contact_name", "emergency_contact_number",
        "emergency_contact_relationship", "job_title",
        "department", "line_manager", "hire_date", "confirmation_date",
        "employment_status", "work_location_type", "base_salary",
        "equipment_needed", "remarks",
        "work_email",
    }
    updates = {k: v for k, v in body.items() if k in updatable}

    if "work_email" in updates:
        new_email = updates["work_email"].strip().lower()
        clash = users.find_one({"email": new_email, "employee_id": {"$ne": employee_id}})
        if clash:
            return jsonify({"message": "Another account already uses this work email."}), 409
        updates["work_email"] = new_email
        updates["email"] = new_email

    if reset_password:
        import secrets
        new_password = secrets.token_urlsafe(9)
        updates["password_hash"] = bcrypt.hashpw(new_password.encode("utf-8"), bcrypt.gensalt())

    updates["updated_by"] = g.current_user["email"]
    updates["updated_at"] = datetime.now(timezone.utc).isoformat()

    users.update_one({"employee_id": employee_id}, {"$set": updates})
    return jsonify({"message": "Employee updated."}), 200


@app.delete("/api/employees/<employee_id>")
@require_hr
def delete_employee(employee_id):
    body = request.get_json(silent=True) or {}
    if body.get("confirm_employee_id") != employee_id:
        return jsonify({"message": "Confirmation ID did not match. Nothing was deleted."}), 400

    result = users.delete_one({"employee_id": employee_id, "role": "employee"})
    if result.deleted_count == 0:
        return jsonify({"message": "Employee not found."}), 404

    return jsonify({"message": "Employee deleted."}), 200


# ---------- Onboarding ----------
# A deliberately separate, HR-triggered workflow — Employees/registration
# does not auto-start this. HR picks a registered employee on the
# Onboarding tab, reviews an AI-drafted (or template) welcome email, sends
# it, and tracks progress via the confirm link the employee clicks plus two
# manually-marked steps (IT equipment, orientation) until those modules
# exist as real features.

ONBOARDING_MANUAL_STEPS = {"it_equipment_ready", "orientation_scheduled"}


def _default_onboarding_status():
    return {
        "started": False, "started_at": None, "started_by": None,
        "welcome_email_sent": False, "welcome_email_sent_at": None,
        "email_subject": None, "email_body": None, "confirm_token": None,
        "email_confirmed": False, "email_confirmed_at": None,
        "it_equipment_ready": False, "it_equipment_ready_at": None,
        "orientation_scheduled": False, "orientation_scheduled_at": None,
    }


@app.get("/api/onboarding/candidates")
@require_hr
def onboarding_candidates():
    """Feeds the employee picker on the Onboarding tab."""
    docs = list(users.find({"role": "employee"}).sort("created_at", -1))
    out = []
    for d in docs:
        status = d.get("onboarding_status") or {}
        out.append({
            "employee_id": d["employee_id"],
            "full_name": d["full_name"],
            "department": d.get("department"),
            "job_title": d.get("job_title"),
            "onboarding_started": status.get("started", False),
        })
    return jsonify({"candidates": out}), 200


@app.post("/api/onboarding/<employee_id>/auto-start")
@require_hr
def onboarding_auto_start(employee_id):
    """The one-click automation entry point: drafts the welcome email via
    Claude and auto-books an orientation slot via the same conflict-checker
    behind Smart Scheduling — both in one call, instead of HR doing them
    as two separate manual steps. Marks onboarding as started immediately
    so progress tracking (and the employee's own checklist/notifications)
    begins right away. Deliberately does NOT send the email itself — HR
    still reviews the draft this returns and calls the existing
    /send-email endpoint when ready, so nothing goes to a new hire's
    inbox without a human looking at it first."""
    doc = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not doc:
        return jsonify({"message": "Employee not found."}), 404

    draft = draft_welcome_email(
        doc["full_name"], doc["job_title"], doc["department"], doc["work_email"], "",
    )

    slot = _find_next_available_slot(DEFAULT_SESSION_MINUTES)
    now = datetime.now(timezone.utc).isoformat()
    updates = {
        "onboarding_status.started": True,
        "onboarding_status.started_by": g.current_user["email"],
    }
    existing_status = doc.get("onboarding_status") or {}
    if not existing_status.get("started"):
        updates["onboarding_status.started_at"] = now

    if slot is not None:
        bookings.insert_one({
            "employee_id": employee_id,
            "employee_name": doc["full_name"],
            "session_type": "orientation",
            "title": SESSION_TYPES["orientation"],
            "date": slot["date"],
            "start_time": slot["start_time"],
            "duration_minutes": slot["duration_minutes"],
            "location": "",
            "created_at": now,
        })
        updates["onboarding_status.orientation_scheduled"] = True
        updates["onboarding_status.orientation_scheduled_at"] = now

    users.update_one({"employee_id": employee_id}, {"$set": updates})

    return jsonify({
        "subject": draft["subject"],
        "body": draft["body"],
        "orientation": slot,  # null if no free slot was found in the next 14 days
    }), 200


@app.post("/api/onboarding/<employee_id>/draft-email")
@require_hr
def onboarding_draft_email(employee_id):
    doc = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not doc:
        return jsonify({"message": "Employee not found."}), 404

    instruction = (request.get_json(silent=True) or {}).get("instruction", "")
    draft = draft_welcome_email(
        doc["full_name"], doc["job_title"], doc["department"], doc["work_email"], instruction,
    )
    return jsonify(draft), 200


@app.post("/api/onboarding/<employee_id>/send-email")
@require_hr
def onboarding_send_email(employee_id):
    doc = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not doc:
        return jsonify({"message": "Employee not found."}), 404

    body = request.get_json(silent=True) or {}
    subject = (body.get("subject") or "").strip()
    body_text = (body.get("body") or "").strip()
    if not subject or not body_text:
        return jsonify({"message": "Subject and body are required."}), 400

    token = secrets.token_urlsafe(24)
    confirm_url = f"{request.host_url.rstrip('/')}/api/onboarding/confirm/{token}"

    try:
        send_email(to_email=doc["personal_email"], subject=subject,
                    html_body=_welcome_email_html(body_text, confirm_url))
    except Exception as exc:
        return jsonify({"message": f"Could not send email: {exc}"}), 502

    now = datetime.now(timezone.utc).isoformat()
    existing = doc.get("onboarding_status") or {}
    users.update_one({"employee_id": employee_id}, {"$set": {
        "onboarding_status.started": True,
        "onboarding_status.started_at": existing.get("started_at") or now,
        "onboarding_status.started_by": g.current_user["email"],
        "onboarding_status.welcome_email_sent": True,
        "onboarding_status.welcome_email_sent_at": now,
        "onboarding_status.email_subject": subject,
        "onboarding_status.email_body": body_text,
        "onboarding_status.confirm_token": token,
        "onboarding_status.email_confirmed": False,
        "onboarding_status.email_confirmed_at": None,
    }})

    return jsonify({"message": f"Email sent to {doc['personal_email']}."}), 200


@app.get("/api/onboarding/confirm/<token>")
def onboarding_confirm(token):
    """Public — no HR auth. The employee reaches this by clicking the link
    in their own inbox, not by logging into SELMS."""
    doc = users.find_one({"onboarding_status.confirm_token": token})
    if not doc:
        return "<h3>This confirmation link is invalid or has expired.</h3>", 404

    if not doc.get("onboarding_status", {}).get("email_confirmed"):
        users.update_one({"_id": doc["_id"]}, {"$set": {
            "onboarding_status.email_confirmed": True,
            "onboarding_status.email_confirmed_at": datetime.now(timezone.utc).isoformat(),
        }})

    return f"<h3>Thanks, {doc['full_name']} — confirmed. You can close this tab.</h3>", 200


@app.get("/api/onboarding/<employee_id>/status")
@require_hr
def onboarding_status(employee_id):
    doc = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not doc:
        return jsonify({"message": "Employee not found."}), 404
    status = doc.get("onboarding_status") or _default_onboarding_status()
    return jsonify(status), 200


@app.post("/api/onboarding/<employee_id>/mark-step")
@require_hr
def onboarding_mark_step(employee_id):
    """Manual checkpoint for the two steps that don't have a real module
    behind them yet (IT equipment tracking, Smart Scheduling). HR marks
    these done by hand until those features exist."""
    step = (request.get_json(silent=True) or {}).get("step")
    if step not in ONBOARDING_MANUAL_STEPS:
        return jsonify({"message": "Unrecognised step."}), 400

    doc = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not doc:
        return jsonify({"message": "Employee not found."}), 404

    users.update_one({"employee_id": employee_id}, {"$set": {
        f"onboarding_status.{step}": True,
        f"onboarding_status.{step}_at": datetime.now(timezone.utc).isoformat(),
    }})
    return jsonify({"message": "Updated."}), 200


# ---------- Employee self-service ----------
#
# Everything an employee's own mobile session can see or do about
# themselves: profile, onboarding checklist, and signing the standard
# company documents. Always scoped to g.current_employee (set by
# require_employee from the JWT), never to an employee_id in the URL.

COMPANY_DOCUMENTS = [
    {"id": "employee_handbook", "title": "Employee Handbook", "description": "Company policies and procedures"},
    {"id": "it_policy", "title": "IT Policy", "description": "Acceptable use of IT resources"},
    {"id": "code_of_conduct", "title": "Code of Conduct", "description": "Professional standards and ethics"},
]


@app.get("/api/employee/me")
@require_employee
def employee_me():
    return jsonify(_employee_public_view(g.current_employee)), 200


@app.post("/api/employee/me/photo")
@require_employee
def employee_upload_own_photo():
    """Same save/record logic as HR's upload_employee_photo, just scoped to
    the caller's own record instead of an HR-supplied employee_id."""
    file = request.files.get("photo")
    if file is None or file.filename == "":
        return jsonify({"message": "No photo file was sent."}), 400

    ext = file.filename.rsplit(".", 1)[-1].lower() if "." in file.filename else ""
    if ext not in ALLOWED_PHOTO_EXTENSIONS:
        return jsonify({"message": "Photo must be a JPG or PNG file."}), 400

    employee_id = g.current_employee["employee_id"]
    filename = secure_filename(f"{employee_id}.{ext}")
    file.save(os.path.join(UPLOAD_FOLDER, filename))

    profile_image_url = f"/uploads/{filename}"
    users.update_one({"_id": g.current_employee["_id"]}, {"$set": {"profile_image_url": profile_image_url}})

    return jsonify({"message": "Photo uploaded.", "profile_image_url": profile_image_url}), 200


@app.get("/api/employee/me/checklist")
@require_employee
def employee_checklist():
    """The 5-item onboarding checklist from the report (fig 3.28), derived
    from onboarding_status and signed_documents rather than duplicated
    into its own field — one source of truth for how far onboarding has
    progressed, whether HR or the employee is looking at it."""
    status = g.current_employee.get("onboarding_status") or _default_onboarding_status()
    has_photo = bool(g.current_employee.get("profile_image_url"))
    signed = g.current_employee.get("signed_documents") or {}
    all_signed = len(signed) >= len(COMPANY_DOCUMENTS)

    items = [
        {"id": "welcome_email", "label": "Welcome Email Received",
         "done": status.get("welcome_email_sent", False), "done_at": status.get("welcome_email_sent_at")},
        {"id": "documents_signed", "label": "Pre-boarding Documents Signed",
         "done": all_signed, "done_at": None},
        {"id": "orientation", "label": "Orientation Session",
         "done": status.get("orientation_scheduled", False), "done_at": status.get("orientation_scheduled_at")},
        {"id": "it_equipment", "label": "Collect IT Equipment",
         "done": status.get("it_equipment_ready", False), "done_at": status.get("it_equipment_ready_at")},
        {"id": "profile_setup", "label": "Complete Profile Setup",
         "done": has_photo, "done_at": None},
    ]

    completed = sum(1 for i in items if i["done"])
    return jsonify({
        "items": items,
        "progress_percent": round(completed / len(items) * 100),
    }), 200


@app.get("/api/employee/me/documents")
@require_employee
def employee_documents():
    signed = g.current_employee.get("signed_documents") or {}
    out = [
        {**d, "signed": d["id"] in signed, "signed_at": signed.get(d["id"])}
        for d in COMPANY_DOCUMENTS
    ]
    return jsonify({"documents": out}), 200


@app.post("/api/employee/me/documents/<doc_id>/sign")
@require_employee
def employee_sign_document(doc_id):
    if doc_id not in {d["id"] for d in COMPANY_DOCUMENTS}:
        return jsonify({"message": "Unknown document."}), 404

    now = datetime.now(timezone.utc).isoformat()
    users.update_one(
        {"_id": g.current_employee["_id"]},
        {"$set": {f"signed_documents.{doc_id}": now}},
    )
    return jsonify({"message": "Signed.", "signed_at": now}), 200


@app.put("/api/employee/me/profile")
@require_employee
def employee_update_own_profile():
    """Deliberately narrow — an employee can correct their own contact
    details, nothing that affects payroll, role, or compliance records
    (those stay HR-only via PUT /api/employees/<id>)."""
    body = request.get_json(silent=True) or {}
    updates = {}
    if "mobile_number" in body:
        value = (body.get("mobile_number") or "").strip()
        if not value:
            return jsonify({"message": "Mobile number cannot be empty."}), 400
        updates["mobile_number"] = value
    if "personal_email" in body:
        value = (body.get("personal_email") or "").strip().lower()
        if not value:
            return jsonify({"message": "Personal email cannot be empty."}), 400
        updates["personal_email"] = value

    if not updates:
        return jsonify({"message": "Nothing to update."}), 400

    users.update_one({"_id": g.current_employee["_id"]}, {"$set": updates})
    return jsonify({"message": "Profile updated."}), 200


@app.get("/api/employee/me/notifications")
@require_employee
def employee_notifications():
    """Every timestamped event on this employee's own record, newest
    first. There's no separate notifications collection — like the
    checklist, this is derived straight from the fields HR/IT already
    write to, so it can never drift out of sync with what actually
    happened. Read state is a single 'read everything before this
    timestamp' marker rather than per-notification flags."""
    emp = g.current_employee
    onboarding = emp.get("onboarding_status") or {}
    offboarding = emp.get("offboarding_status") or {}
    signed = emp.get("signed_documents") or {}
    read_before = emp.get("notifications_read_at")

    events = []
    if onboarding.get("welcome_email_sent_at"):
        events.append(("welcome_email", "Welcome email sent",
                        "Your onboarding has started.", onboarding["welcome_email_sent_at"]))
    if onboarding.get("orientation_scheduled_at"):
        events.append(("orientation_scheduled", "Orientation session scheduled",
                        "HR has scheduled your orientation.", onboarding["orientation_scheduled_at"]))
    if onboarding.get("it_equipment_ready_at"):
        events.append(("it_equipment_ready", "IT equipment ready",
                        "Your equipment is ready for collection.", onboarding["it_equipment_ready_at"]))

    doc_titles = {d["id"]: d["title"] for d in COMPANY_DOCUMENTS}
    for doc_id, signed_at in signed.items():
        events.append((f"doc_signed_{doc_id}", f"You signed {doc_titles.get(doc_id, doc_id)}",
                        "Document acknowledged.", signed_at))

    if offboarding.get("started_at"):
        events.append(("offboarding_started", "Offboarding started",
                        f"Last working day: {offboarding.get('last_working_day') or 'TBC'}.",
                        offboarding["started_at"]))
    if offboarding.get("exit_interview_scheduled_at"):
        events.append(("exit_interview_scheduled", "Exit interview scheduled",
                        "HR has scheduled your exit interview.", offboarding["exit_interview_scheduled_at"]))
    if offboarding.get("access_revoked_at"):
        events.append(("access_revoked", "System access revoked",
                        "Your company system access has been revoked.", offboarding["access_revoked_at"]))

    events.sort(key=lambda e: e[3], reverse=True)
    out = [
        {"id": eid, "title": title, "message": msg, "at": at,
         "read": bool(read_before) and read_before >= at}
        for eid, title, msg, at in events
    ]
    return jsonify({"notifications": out, "unread_count": sum(1 for n in out if not n["read"])}), 200


@app.post("/api/employee/me/notifications/mark-read")
@require_employee
def employee_mark_notifications_read():
    now = datetime.now(timezone.utc).isoformat()
    users.update_one({"_id": g.current_employee["_id"]}, {"$set": {"notifications_read_at": now}})
    return jsonify({"message": "Marked as read.", "read_at": now}), 200


@app.get("/api/employee/me/offboarding")
@require_employee
def employee_offboarding():
    """Mirrors the onboarding checklist, but only meaningful once HR has
    actually initiated offboarding for this employee — until then there's
    nothing to show, so the Offboarding tab stays hidden client-side."""
    status = g.current_employee.get("offboarding_status") or _default_offboarding_status()
    if not status.get("started"):
        return jsonify({"started": False}), 200

    employee_id = g.current_employee["employee_id"]
    equipment_outstanding = equipment.count_documents({
        "assigned_to_employee_id": employee_id, "status": "assigned",
    })

    items = [
        {"id": "departure_recorded", "label": "Departure Recorded",
         "done": True, "done_at": status.get("started_at")},
        {"id": "exit_interview", "label": "Exit Interview",
         "done": status.get("exit_interview_scheduled", False),
         "done_at": status.get("exit_interview_scheduled_at")},
        {"id": "equipment_returned", "label": "Equipment Returned",
         "done": equipment_outstanding == 0, "done_at": None},
        {"id": "access_revoked", "label": "IT Access Revoked",
         "done": status.get("access_revoked", False), "done_at": status.get("access_revoked_at")},
    ]
    completed = sum(1 for i in items if i["done"])

    return jsonify({
        "started": True,
        "departure_type": status.get("departure_type"),
        "last_working_day": status.get("last_working_day"),
        "items": items,
        "progress_percent": round(completed / len(items) * 100),
    }), 200


# ---------- Offboarding status (real per-employee tracking) ----------
#
# Separate from the offboarding *flow builder* below, which only edits the
# shape of the automation template/per-employee node chain. This is the
# actual "HR marked this employee as departing" state — the thing the
# report's fig 3.12 "Initiate Offboarding" popup describes but that had
# no backend behind it until now.

OFFBOARDING_MANUAL_STEPS = {"exit_interview_scheduled", "access_revoked"}


def _default_offboarding_status():
    return {
        "started": False, "started_at": None, "started_by": None,
        "departure_type": None, "last_working_day": None, "notes": None,
        "exit_interview_scheduled": False, "exit_interview_scheduled_at": None,
        "access_revoked": False, "access_revoked_at": None,
    }


@app.post("/api/employees/<employee_id>/offboarding/initiate")
@require_hr
def initiate_offboarding(employee_id):
    doc = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not doc:
        return jsonify({"message": "Employee not found."}), 404

    body = request.get_json(silent=True) or {}
    departure_type = (body.get("departure_type") or "").strip()
    last_working_day = (body.get("last_working_day") or "").strip()
    if not departure_type or not last_working_day:
        return jsonify({"message": "Departure type and last working day are required."}), 400

    now = datetime.now(timezone.utc).isoformat()
    users.update_one({"employee_id": employee_id}, {"$set": {
        "offboarding_status.started": True,
        "offboarding_status.started_at": now,
        "offboarding_status.started_by": g.current_user["email"],
        "offboarding_status.departure_type": departure_type,
        "offboarding_status.last_working_day": last_working_day,
        "offboarding_status.notes": (body.get("notes") or "").strip(),
    }})
    return jsonify({"message": "Offboarding initiated."}), 200


@app.get("/api/employees/<employee_id>/offboarding")
@require_hr
def get_employee_offboarding(employee_id):
    """HR's view of the same computation employee_offboarding does for
    'me' — same shape, just addressed by employee_id instead of the
    caller's own token."""
    doc = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not doc:
        return jsonify({"message": "Employee not found."}), 404

    status = doc.get("offboarding_status") or _default_offboarding_status()
    if not status.get("started"):
        return jsonify({"started": False}), 200

    equipment_outstanding = equipment.count_documents({
        "assigned_to_employee_id": employee_id, "status": "assigned",
    })
    items = [
        {"id": "departure_recorded", "label": "Departure Recorded",
         "done": True, "done_at": status.get("started_at")},
        {"id": "exit_interview", "label": "Exit Interview",
         "done": status.get("exit_interview_scheduled", False),
         "done_at": status.get("exit_interview_scheduled_at")},
        {"id": "equipment_returned", "label": "Equipment Returned",
         "done": equipment_outstanding == 0, "done_at": None},
        {"id": "access_revoked", "label": "IT Access Revoked",
         "done": status.get("access_revoked", False), "done_at": status.get("access_revoked_at")},
    ]
    completed = sum(1 for i in items if i["done"])

    return jsonify({
        "started": True,
        "departure_type": status.get("departure_type"),
        "last_working_day": status.get("last_working_day"),
        "notes": status.get("notes"),
        "items": items,
        "progress_percent": round(completed / len(items) * 100),
    }), 200


@app.post("/api/offboarding/<employee_id>/mark-step")
@require_hr
def offboarding_mark_step(employee_id):
    """Manual checkpoint for the two offboarding steps that don't have a
    real module behind them yet (exit interview, access revocation) —
    same pattern as onboarding_mark_step. Equipment return is never
    manual: it's computed live from the equipment collection instead."""
    step = (request.get_json(silent=True) or {}).get("step")
    if step not in OFFBOARDING_MANUAL_STEPS:
        return jsonify({"message": "Unrecognised step."}), 400

    doc = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not doc:
        return jsonify({"message": "Employee not found."}), 404

    users.update_one({"employee_id": employee_id}, {"$set": {
        f"offboarding_status.{step}": True,
        f"offboarding_status.{step}_at": datetime.now(timezone.utc).isoformat(),
    }})
    return jsonify({"message": "Updated."}), 200


# --- Onboarding automation flow builder ---
#
# One "template" document (_id: "template") is the reusable default every
# new hire starts from. The first time HR opens a specific employee's flow,
# it's copied out of the template into its own document keyed by
# employee_id — editing that employee's copy never touches the template or
# any other employee's copy.
#
# A node is either:
#   {"id", "type": "action", "icon", "label", "sub"}
#   {"id", "type": "condition", "label", "sub",
#    "branch_a_label", "branch_b_label", "branch_a": [nodes], "branch_b": [nodes]}
# Branches hold action nodes only (no nesting a condition inside a branch,
# to keep this from turning into a full workflow engine).

def _default_flow_nodes():
    return [
        {"id": "trigger", "type": "action", "icon": "ti-user-plus",
         "label": "Employee details inserted", "sub": "Trigger — starts this flow", "locked": True},
        {"id": str(uuid.uuid4()), "type": "action", "icon": "ti-mail",
         "label": "Send welcome email", "sub": "AI-drafted, then sent"},
        {"id": str(uuid.uuid4()), "type": "condition",
         "label": "Condition — work location type", "sub": "Splits into two paths below",
         "branch_a_label": "If onsite", "branch_b_label": "If remote",
         "branch_a": [{"id": str(uuid.uuid4()), "type": "action", "icon": "ti-truck-delivery",
                        "label": "Prepare laptop", "sub": "For pickup"}],
         "branch_b": [{"id": str(uuid.uuid4()), "type": "action", "icon": "ti-package",
                        "label": "Arrange courier", "sub": "Ship to home"}]},
        {"id": str(uuid.uuid4()), "type": "action", "icon": "ti-calendar",
         "label": "Schedule orientation", "sub": "Auto-assigned slot"},
    ]


@app.get("/api/onboarding-flows/template")
@require_hr
def get_flow_template():
    doc = onboarding_flows.find_one({"_id": "template"})
    if not doc:
        doc = {"_id": "template", "nodes": _default_flow_nodes()}
        onboarding_flows.insert_one(doc)
    return jsonify({"nodes": doc["nodes"]}), 200


@app.put("/api/onboarding-flows/template")
@require_hr
def save_flow_template():
    nodes = (request.get_json(silent=True) or {}).get("nodes")
    if not isinstance(nodes, list):
        return jsonify({"message": "nodes must be a list."}), 400
    onboarding_flows.update_one({"_id": "template"}, {"$set": {"nodes": nodes}}, upsert=True)
    return jsonify({"message": "Template saved."}), 200


@app.get("/api/onboarding-flows/employee/<employee_id>")
@require_hr
def get_employee_flow(employee_id):
    emp = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not emp:
        return jsonify({"message": "Employee not found."}), 404

    doc = onboarding_flows.find_one({"_id": employee_id})
    if not doc:
        template = onboarding_flows.find_one({"_id": "template"})
        nodes = template["nodes"] if template else _default_flow_nodes()
        doc = {"_id": employee_id, "nodes": nodes}
        onboarding_flows.insert_one(doc)
    return jsonify({"nodes": doc["nodes"]}), 200


@app.put("/api/onboarding-flows/employee/<employee_id>")
@require_hr
def save_employee_flow(employee_id):
    emp = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not emp:
        return jsonify({"message": "Employee not found."}), 404

    nodes = (request.get_json(silent=True) or {}).get("nodes")
    if not isinstance(nodes, list):
        return jsonify({"message": "nodes must be a list."}), 400
    onboarding_flows.update_one({"_id": employee_id}, {"$set": {"nodes": nodes}}, upsert=True)
    return jsonify({"message": "Flow saved."}), 200


# --- Offboarding automation flow builder ---
#
# Same template/per-employee-copy pattern as onboarding, in its own
# collection so the two never collide. Default steps map onto the report's
# 5-phase offboarding process (2.1.3): notification, exit interview,
# knowledge transfer, paperwork, IT access & security.

def _default_offboarding_nodes():
    return [
        {"id": "trigger", "type": "action", "icon": "ti-logout",
         "label": "Offboarding initiated", "sub": "Trigger — starts this flow", "locked": True},
        {"id": str(uuid.uuid4()), "type": "action", "icon": "ti-mail",
         "label": "Notify manager & HR", "sub": "Departure confirmed within 24h"},
        {"id": str(uuid.uuid4()), "type": "action", "icon": "ti-calendar",
         "label": "Schedule exit interview", "sub": "Auto-assigned slot"},
        {"id": str(uuid.uuid4()), "type": "action", "icon": "ti-checklist",
         "label": "Knowledge transfer checklist", "sub": "SOPs handed to successor"},
        {"id": str(uuid.uuid4()), "type": "action", "icon": "ti-file-text",
         "label": "Finalize payroll & benefits", "sub": "Last pay, insurance continuation"},
        {"id": str(uuid.uuid4()), "type": "action", "icon": "ti-qrcode",
         "label": "Retrieve IT equipment", "sub": "Handled from the IT app"},
        {"id": str(uuid.uuid4()), "type": "action", "icon": "ti-lock",
         "label": "Revoke system access", "sub": "Email, cloud storage, network"},
    ]


@app.get("/api/offboarding-flows/template")
@require_hr
def get_offboarding_flow_template():
    doc = offboarding_flows.find_one({"_id": "template"})
    if not doc:
        doc = {"_id": "template", "nodes": _default_offboarding_nodes()}
        offboarding_flows.insert_one(doc)
    return jsonify({"nodes": doc["nodes"]}), 200


@app.put("/api/offboarding-flows/template")
@require_hr
def save_offboarding_flow_template():
    nodes = (request.get_json(silent=True) or {}).get("nodes")
    if not isinstance(nodes, list):
        return jsonify({"message": "nodes must be a list."}), 400
    offboarding_flows.update_one({"_id": "template"}, {"$set": {"nodes": nodes}}, upsert=True)
    return jsonify({"message": "Template saved."}), 200


@app.get("/api/offboarding-flows/employee/<employee_id>")
@require_hr
def get_offboarding_employee_flow(employee_id):
    emp = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not emp:
        return jsonify({"message": "Employee not found."}), 404

    doc = offboarding_flows.find_one({"_id": employee_id})
    if not doc:
        template = offboarding_flows.find_one({"_id": "template"})
        nodes = template["nodes"] if template else _default_offboarding_nodes()
        doc = {"_id": employee_id, "nodes": nodes}
        offboarding_flows.insert_one(doc)
    return jsonify({"nodes": doc["nodes"]}), 200


@app.put("/api/offboarding-flows/employee/<employee_id>")
@require_hr
def save_offboarding_employee_flow(employee_id):
    emp = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not emp:
        return jsonify({"message": "Employee not found."}), 404

    nodes = (request.get_json(silent=True) or {}).get("nodes")
    if not isinstance(nodes, list):
        return jsonify({"message": "nodes must be a list."}), 400
    offboarding_flows.update_one({"_id": employee_id}, {"$set": {"nodes": nodes}}, upsert=True)
    return jsonify({"message": "Flow saved."}), 200


# --- Smart Schedule (bookings) ---
#
# HR-only. A booking is a single session on the calendar: an onboarding
# orientation, an IT handoff, an offboarding exit interview, or a manually
# added session. "Smart" scheduling means checking existing bookings
# before suggesting a slot — not a real external calendar integration,
# just conflict-checking against what SELMS itself already knows about.

WORKDAY_START_MINUTES = 9 * 60   # 9:00 AM
WORKDAY_END_MINUTES = 17 * 60    # 5:00 PM
DEFAULT_SESSION_MINUTES = 30

SESSION_TYPES = {
    "orientation": "Orientation",
    "it_handoff": "IT Handoff",
    "exit_interview": "Exit Interview",
    "other": "Other",
}


def _time_to_minutes(hhmm):
    h, m = hhmm.split(":")
    return int(h) * 60 + int(m)


def _minutes_to_time(total):
    return f"{total // 60:02d}:{total % 60:02d}"


def _booking_overlaps(a_start, a_end, b_start, b_end):
    return a_start < b_end and b_start < a_end


@app.post("/api/bookings")
@require_hr
def create_booking():
    body = request.get_json(silent=True) or {}
    employee_id = (body.get("employee_id") or "").strip()
    employee_name = (body.get("employee_name") or "").strip()
    session_type = body.get("session_type") or "other"
    date = (body.get("date") or "").strip()          # "YYYY-MM-DD"
    start_time = (body.get("start_time") or "").strip()  # "HH:MM"
    duration_minutes = body.get("duration_minutes") or DEFAULT_SESSION_MINUTES
    location = (body.get("location") or "").strip()
    title = (body.get("title") or SESSION_TYPES.get(session_type, "Session")).strip()

    if not date or not start_time:
        return jsonify({"message": "date and start_time are required."}), 400
    if session_type not in SESSION_TYPES:
        return jsonify({"message": "Unrecognised session_type."}), 400

    doc = {
        "employee_id": employee_id,
        "employee_name": employee_name,
        "session_type": session_type,
        "title": title,
        "date": date,
        "start_time": start_time,
        "duration_minutes": duration_minutes,
        "location": location,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    result = bookings.insert_one(doc)
    doc["_id"] = str(result.inserted_id)
    return jsonify(doc), 201


@app.get("/api/bookings")
@require_hr
def list_bookings():
    """?start=YYYY-MM-DD&end=YYYY-MM-DD — inclusive date range, meant for
    one week at a time from the Smart Schedule calendar."""
    start = request.args.get("start")
    end = request.args.get("end")
    query = {}
    if start and end:
        query["date"] = {"$gte": start, "$lte": end}
    docs = []
    for d in bookings.find(query).sort([("date", 1), ("start_time", 1)]):
        d["_id"] = str(d["_id"])
        docs.append(d)
    return jsonify({"bookings": docs}), 200


def _find_next_available_slot(duration_minutes):
    """Looks 14 days ahead from today, finds the first work-hours slot of
    the requested duration that doesn't overlap any existing booking.
    Simple linear scan — fine at this scale, not meant to be a production
    optimizer. Returns {date, start_time, duration_minutes} or None.
    Shared by the manual GET /api/bookings/suggest route and the
    automated onboarding flow below, so "smart scheduling" means the
    same thing in both places."""
    today = datetime.now(timezone.utc).date()
    for day_offset in range(14):
        day = today + timedelta(days=day_offset)
        if day.weekday() >= 5:  # skip Sat/Sun
            continue
        date_str = day.isoformat()
        day_bookings = list(bookings.find({"date": date_str}))
        busy = []
        for b in day_bookings:
            b_start = _time_to_minutes(b["start_time"])
            b_end = b_start + int(b.get("duration_minutes") or DEFAULT_SESSION_MINUTES)
            busy.append((b_start, b_end))

        slot_start = WORKDAY_START_MINUTES
        while slot_start + duration_minutes <= WORKDAY_END_MINUTES:
            slot_end = slot_start + duration_minutes
            if not any(_booking_overlaps(slot_start, slot_end, b[0], b[1]) for b in busy):
                return {
                    "date": date_str,
                    "start_time": _minutes_to_time(slot_start),
                    "duration_minutes": duration_minutes,
                }
            slot_start += 30  # step forward in 30-minute increments

    return None


@app.get("/api/bookings/suggest")
@require_hr
def suggest_booking_slot():
    slot = _find_next_available_slot(int(request.args.get("duration_minutes") or DEFAULT_SESSION_MINUTES))
    if slot is None:
        return jsonify({"message": "No free slot found in the next 14 days."}), 404
    return jsonify(slot), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
