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
    pip install flask flask-cors pymongo bcrypt pyjwt openpyxl python-dotenv pypdf python-docx --break-system-packages
    Create a .env file in this folder (see .env.example) with MONGO_URI,
    JWT_SECRET, SMTP_USER, SMTP_PASSWORD — loaded automatically below, so
    no $env:... lines are needed before running this.
    python selms_backend.py
"""

import os
import re
import threading
import secrets
import smtplib
import ssl
import urllib.error
import urllib.parse
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
from dotenv import load_dotenv
from flask import Flask, request, jsonify, g, send_file, send_from_directory
from flask_cors import CORS
from pymongo import MongoClient
from openpyxl import Workbook
from werkzeug.utils import secure_filename

# Loads .env (same folder as this file) into the environment if present —
# values already set via $env:/export still take priority, so this is
# purely a convenience default, not a hidden override.
load_dotenv()

MONGO_URI = os.environ.get("MONGO_URI", "mongodb://localhost:27017")
DB_NAME = os.environ.get("SELMS_DB", "selms")
JWT_SECRET = os.environ.get("JWT_SECRET", "dev-secret-change-me")
JWT_EXPIRY_HOURS = 8
VALID_ROLES = {"hr", "it", "employee"}

# Used only for the confirm-you've-received-this link in onboarding
# emails — that link gets opened on an employee's own device, which
# `localhost` never resolves correctly on, unlike every other API call
# the HR app makes (those stay on localhost/LAN, unaffected by this).
# Set to a tunnel (ngrok) or real public URL when you need that link to
# actually be reachable from outside this machine; leave unset otherwise
# and it falls back to whatever host the request itself arrived on.
PUBLIC_BASE_URL = os.environ.get("PUBLIC_BASE_URL", "").rstrip("/")

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

# Google Calendar / Meet - see the "Google Calendar / Meet" section below.
GOOGLE_CLIENT_ID = os.environ.get("GOOGLE_CLIENT_ID", "")
GOOGLE_CLIENT_SECRET = os.environ.get("GOOGLE_CLIENT_SECRET", "")
GOOGLE_REDIRECT_URI = os.environ.get("GOOGLE_REDIRECT_URI", "http://localhost:5000/api/google/callback")
SCHEDULE_TIMEZONE = os.environ.get("SCHEDULE_TIMEZONE", "Asia/Kuala_Lumpur")
# Optional fallback for online sessions when Google isn't connected:
# a standing HR Meet/Teams room link used instead of leaving the link blank.
DEFAULT_MEETING_URL = os.environ.get("DEFAULT_MEETING_URL", "")
ANTHROPIC_MODEL = os.environ.get("ANTHROPIC_MODEL", "claude-sonnet-4-6")

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 11 * 1024 * 1024  # 10MB documents + headroom; photos are capped below
CORS(app)  # needed since the Flutter web app runs on a different origin


@app.before_request
def _cap_photo_uploads():
    if request.method == "POST" and request.path.endswith("/photo") \
            and (request.content_length or 0) > MAX_PHOTO_BYTES + (1 * 1024 * 1024):
        return jsonify({"message": "That photo is too large (5MB maximum)."}), 413

client = MongoClient(MONGO_URI)
db = client[DB_NAME]
users = db["users"]
onboarding_flows = db["onboarding_flows"]
offboarding_flows = db["offboarding_flows"]
equipment = db["equipment"]
bookings = db["bookings"]
messages = db["messages"]
settings = db["settings"]  # small key/value docs, e.g. the Google connection
shipments = db["shipments"]  # Pos Malaysia parcels: equipment out to / back from employees


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
        text = "".join(b.get("text", "") for b in data.get("content", []) if b.get("type") == "text").strip()
        # Model may wrap JSON in ```json fences despite instructions — strip them.
        text = text.removeprefix("```json").removeprefix("```").removesuffix("```").strip()
        parsed = _json.loads(text)
        return {"subject": parsed["subject"], "body": parsed["body"]}
    except Exception as exc:  # noqa: BLE001 — any failure just falls back
        print(f"[AI draft] falling back to template: {exc}")
        return _fallback_welcome_email(full_name, job_title, department, work_email)


def _booking_summary(booking):
    """Plain facts about a booking for emails/checklists, or None."""
    if not booking:
        return None
    return {
        "title": booking.get("title"),
        "date": booking.get("date"),
        "start_time": booking.get("start_time"),
        "duration_minutes": booking.get("duration_minutes"),
        "mode": booking.get("mode") or "in_person",
        "location": booking.get("location") or "",
        "meeting_url": booking.get("meeting_url") or "",
    }


def _orientation_email_block(booking, title="Your orientation") -> str:
    """The 'your orientation' box appended to the welcome email (and, titled
    'Your exit interview', to the offboarding email). Built from the real
    booking (not written by the AI), so the time and link are always the
    ones actually in the schedule."""
    info = _booking_summary(booking)
    if not info:
        return ""
    when = f"{info['date']} at {info['start_time']}"
    mode_label = {"in_person": "In person", "online": "Online"}.get(info["mode"], "In person")
    lines = [f"<strong>{title}:</strong> {when} ({mode_label})"]
    if info["location"]:
        lines.append(f"Location: {info['location']}")
    join = ""
    if info["meeting_url"]:
        join = (f'<p style="margin:10px 0 0"><a href="{info["meeting_url"]}" style="background:#16a34a;'
                f'color:#fff;padding:9px 16px;border-radius:6px;text-decoration:none;display:inline-block">'
                f'Join online</a></p><p style="margin:6px 0 0;font-size:12px;color:#6b7280">{info["meeting_url"]}</p>')
    return (f'<div style="margin-top:18px;padding:14px;border:1px solid #e5e7eb;border-radius:8px;'
            f'background:#f9fafb">{"<br>".join(lines)}{join}</div>')


def _with_sign_in(body, employee_doc):
    """Adds the employee's SELMS sign-in (work email + temporary password) to
    the end of the welcome email text, so HR sees it in the draft and can
    edit it like the rest of the email."""
    email = employee_doc.get("work_email") or employee_doc.get("email") or ""
    temp = employee_doc.get("initial_password")
    lines = ["Your SELMS sign-in", f"Work email: {email}"]
    if temp:
        lines += [f"Temporary password: {temp}",
                  "You will be asked to create your own password when you first sign in."]
    else:
        lines.append("Password: the one you created when you first signed in")
    return (body or "").rstrip() + "\n\n" + "\n".join(lines)


def _credentials_email_block(employee_doc) -> str:
    """The 'how to sign in to SELMS' box in the welcome email: work email and
    HR's temporary password (when we still have it readable), plus the note
    that they'll set their own password on first sign-in."""
    email = employee_doc.get("work_email") or employee_doc.get("email") or ""
    temp = employee_doc.get("initial_password")
    rows = [f"Work email: <strong>{email}</strong>"]
    if temp:
        rows.append(f'Temporary password: <strong style="font-family:monospace;font-size:15px">{temp}</strong>')
    else:
        rows.append("Password: the one you created when you first signed in")
    return (f'<div style="margin-top:18px;padding:14px;border:1px solid #c7d2fe;border-radius:8px;'
            f'background:#eef2ff"><strong>Your SELMS sign-in</strong><br>{"<br>".join(rows)}'
            f'<p style="margin:8px 0 0;font-size:12px;color:#4b5563">Sign in to the SELMS employee app with '
            f'these details. You will be asked to create your own password straight away.</p></div>')


def _ensure_temp_password(employee_id):
    """The welcome email has to tell the new hire how to sign in. If HR's
    temporary password is no longer readable (older accounts) and the
    employee never made their own, issue a fresh one so the email can carry
    it. An employee who already created their own password is left alone."""
    doc = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not doc or doc.get("initial_password") or doc.get("password_changed_at"):
        return
    fresh = _generate_initial_password()
    users.update_one({"employee_id": employee_id}, {"$set": {
        "password_hash": bcrypt.hashpw(fresh.encode("utf-8"), bcrypt.gensalt()),
        "initial_password": fresh,
    }})


def _require_password_reset(employee_id):
    """Onboarding has started: the next sign-in with HR's temporary password
    must go through 'create your password'. Only for someone still on the
    temporary password (never set their own) - an employee who already
    created their own password is left alone."""
    users.update_one({"employee_id": employee_id, "password_changed_at": None},
                     {"$set": {"must_change_password": True}})


def _welcome_email_html(body_text: str, confirm_url: str, orientation_html: str = "",
                        credentials_html: str = "") -> str:
    """Wraps HR's (possibly AI-drafted, possibly edited) plain-text body in
    HTML, with the confirmation link that flips onboarding_status.email_confirmed
    when the employee clicks it."""
    import html as _htmlmod
    paragraphs = "".join(f"<p>{_htmlmod.escape(line)}</p>" for line in body_text.split("\n") if line.strip())
    return f"""
    <div style="font-family:sans-serif;color:#14161b">
      {paragraphs}
      {credentials_html}
      {orientation_html}
      <p style="margin-top:20px">
        <a href="{confirm_url}" style="background:#14161b;color:#fff;padding:10px 18px;
           border-radius:6px;text-decoration:none;display:inline-block">
          Confirm you've received this
        </a>
      </p>
    </div>
    """


# ---------- AI chatbot (HR + Employee only — not IT, per the report's own
# functional requirements table) ----------
#
# Both endpoints below use this same helper. Unlike draft_welcome_email,
# there's no sensible template fallback for open-ended conversation, so
# failures are raised and turned into a clear error message instead.

def _chat_completion(system_prompt: str, messages: list) -> str:
    if not ANTHROPIC_API_KEY:
        raise RuntimeError("ANTHROPIC_API_KEY is not configured on the server.")

    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=_json.dumps({
            "model": ANTHROPIC_MODEL,
            "max_tokens": 500,
            "system": system_prompt,
            "messages": messages,
        }).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "x-api-key": ANTHROPIC_API_KEY,
            "anthropic-version": "2023-06-01",
        },
    )
    with urllib.request.urlopen(req, timeout=20) as res:
        data = _json.loads(res.read())
    # Take every text block - the first block isn't always the text one.
    return "".join(b.get("text", "") for b in data.get("content", []) if b.get("type") == "text").strip()


EMPLOYEE_FAQ = """
Leave: Apply through HR directly for now - a self-service leave form isn't built into SELMS yet, so email or message HR with your requested dates.
Medical claim: Download the claim form from the Documents tab, fill in your details, attach receipts, and submit to HR. Claims are processed within 7 working days.
Equipment collection: Check the Onboarding tab's "Collect IT Equipment" checklist item - IT will mark it complete once your equipment is ready and handed over.
VPN / remote access: Contact IT directly to have VPN access set up on your device; this isn't self-service yet.
Orientation: HR schedules your orientation session automatically once your onboarding starts; check the Onboarding tab for the date once it's confirmed.
""".strip()


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
    if role == "employee" and _login_closed(user):
        return jsonify({"message": "Your SELMS account was closed after your last working day."}), 403

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
        # Still on the temporary password HR sent - the app makes them
        # create their own before going any further.
        "must_change_password": bool(user.get("must_change_password")),
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
        if _login_closed(doc):
            return jsonify({"message": "Your SELMS account was closed after your last working day."}), 401

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
@require_hr_or_it  # HR may view (Products, view only); changes stay IT-only
def get_equipment(equipment_id):
    try:
        doc = equipment.find_one({"_id": ObjectId(equipment_id)})
    except Exception:
        doc = None
    if not doc:
        return jsonify({"message": "Equipment not found."}), 404
    doc["_id"] = str(doc["_id"])
    return jsonify(_with_assignee_photo(doc)), 200


def _with_assignee_photo(doc):
    """The assigned employee's CURRENT photo (the copy stored at assign time
    goes stale, or is empty if they had none yet)."""
    eid = doc.get("assigned_to_employee_id")
    if eid:
        person = users.find_one({"employee_id": eid}, {"profile_image_url": 1}) or {}
        doc["assigned_to_employee_photo_url"] = person.get("profile_image_url") or doc.get(
            "assigned_to_employee_photo_url")
    return doc


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
    _notify("employee", employee_id, "notification", "Equipment assigned",
            f"IT has assigned {result.modified_count} item(s) to you.", {"type": "onboarding"})
    fresh = users.find_one({"employee_id": employee_id}) or employee
    if (fresh.get("onboarding_status") or {}).get("started") and fresh.get("equipment_needed"):
        items, _extra, ready, _at = _equipment_fulfilment(fresh)
        if ready:
            _notify("hr", None, "notification", f"Equipment ready: {fresh.get('full_name')}",
                    "IT has assigned everything requested: " + ", ".join(
                        f"{(i['asset'] or {}).get('name') or i['type']}" for i in items) + ".",
                    {"type": "products"}, dedupe_key=f"equipment-ready:{employee_id}")
    _advance_safely(employee_id)
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
    # Lost: the item is closed off as lost (it never comes back); Damaged: it
    # goes to repair; otherwise it is free to assign again.
    new_status = {"Damaged": "under_repair", "Lost": "lost"}.get(condition_on_return, "available")

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
    if condition_on_return and condition_on_return != "Lost":
        updates["condition"] = condition_on_return

    returned_from = doc.get("assigned_to_employee_id")
    equipment.update_one({"_id": ObjectId(equipment_id)}, {"$set": updates})
    leaver = users.find_one({"employee_id": returned_from, "role": "employee"}) if returned_from else None
    if leaver and (leaver.get("offboarding_status") or {}).get("started"):
        tag = doc.get("asset_tag") or ""
        what = f"{doc.get('name') or doc.get('type') or 'Item'}{f' ({tag})' if tag else ''}"
        if condition_on_return in ("Lost", "Damaged"):
            _notify("hr", None, "notification",
                    f"Equipment {'lost' if condition_on_return == 'Lost' else 'returned damaged'}: {leaver.get('full_name')}",
                    f"{what} was recorded as {'lost' if condition_on_return == 'Lost' else 'damaged (sent for repair)'} by IT.",
                    {"type": "products"})
        if condition_on_return == "Lost":
            title, text = "Equipment recorded as lost", f"IT has recorded {what} as lost. It no longer counts as with you."
        elif condition_on_return == "Damaged":
            title, text = "Equipment received", f"{what} was received by IT (damaged - sent for repair). Thank you!"
        else:
            title, text = "Equipment received", f"{what} was received by IT. Thank you!"
        _notify("employee", returned_from, "notification", title, text, {"type": "offboarding"})
    # Everything back from a remote leaver: their return parcel has clearly
    # arrived, so it's closed off as delivered without another click.
    if leaver and not _equipment_outstanding(returned_from):
        parcel = _return_parcel(leaver)
        if parcel and parcel.get("status") != "delivered":
            shipments.update_one({"_id": parcel["_id"]}, {"$set": {
                "status": "delivered", "delivered_at": datetime.now(timezone.utc).isoformat()}})
            _notify("hr", None, "notification", f"Return parcel received: {leaver.get('full_name')}",
                    "IT has received everything they posted back.", {"type": "shipments"},
                    dedupe_key=f"hr-shipment:{parcel['_id']}:delivered")
    # If this person is being offboarded, the "Retrieve IT equipment" step may
    # now be complete - let the flow move on to what comes next.
    _advance_offboarding_safely(returned_from)
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

    # A new file name per upload (like profile photos) - re-using one name
    # meant the browser kept showing the cached old picture after a replace.
    stamp = int(datetime.now(timezone.utc).timestamp())
    filename = secure_filename(f"equipment-{equipment_id}-{stamp}.{ext}")
    file.save(os.path.join(UPLOAD_FOLDER, filename))
    _delete_upload(doc.get("photo_url"), keep=filename)

    photo_url = f"/uploads/{filename}"
    equipment.update_one({"_id": ObjectId(equipment_id)}, {"$set": {"photo_url": photo_url}})

    return jsonify({"message": "Photo uploaded.", "photo_url": photo_url}), 200


@app.delete("/api/equipment/<equipment_id>/photo")
@require_it
def remove_equipment_photo(equipment_id):
    try:
        doc = equipment.find_one({"_id": ObjectId(equipment_id)})
    except Exception:
        doc = None
    if not doc:
        return jsonify({"message": "Equipment not found."}), 404
    _delete_upload(doc.get("photo_url"))
    equipment.update_one({"_id": doc["_id"]}, {"$set": {"photo_url": None}})
    return jsonify({"message": "Photo removed."}), 200


def _delete_upload(url, keep=None):
    """Removes a file previously saved to UPLOAD_FOLDER, given its public
    /uploads/... path. Missing files are ignored."""
    url = url or ""
    name = os.path.basename(url)
    if url.startswith("/uploads/") and name and name != keep:
        try:
            os.remove(os.path.join(UPLOAD_FOLDER, name))
        except OSError:
            pass


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
@require_hr_or_it  # HR may view (Products, view only); changes stay IT-only
def list_equipment():
    query = _build_equipment_query(request.args)
    items = []
    for doc in equipment.find(query).sort("created_at", -1):
        doc["_id"] = str(doc["_id"])
        items.append(_with_assignee_photo(doc))
    return jsonify({"items": items}), 200


@app.get("/api/equipment/export")
@require_hr_or_it  # read-only, so HR's Products page can export too
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
@require_hr_or_it
def list_equipment_types():
    """Defaults plus any custom type names already in use, so a type someone
    added once shows up for everybody afterwards — not just that session."""
    custom = equipment.distinct("type")
    if request.args.get("only_existing") == "1":
        # Just the types IT has actually created equipment for (HR's
        # "Equipment needed" choices) - not the defaults IT could still pick.
        return jsonify({"types": sorted(t for t in custom if t)}), 200
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
    # Never sent to the browser, but HR is told which kind of password it is.
    out["password_state"] = "temporary" if out.pop("initial_password", None) else (
        "own" if doc.get("password_changed_at") else "unknown")
    out["login_status"] = _login_status_text(doc) if (doc.get("offboarding_status") or {}).get("started") else "Open"
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
        # HR's temporary password, kept readable on purpose: it goes in the
        # welcome email when onboarding starts. Removed the moment the
        # employee creates their own password (which is only ever hashed).
        "initial_password": body["temp_password"],
        # Before onboarding starts they can sign in with it directly; starting
        # onboarding turns this on (see _require_password_reset).
        "must_change_password": False,
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
    docs = list(users.find(query, {"employee_id": 1, "full_name": 1, "department": 1, "profile_image_url": 1,
                                   "hire_date": 1, "work_location_type": 1})
                .sort("full_name", 1).limit(50))
    results = [{"employee_id": d.get("employee_id"), "full_name": d.get("full_name"), "department": d.get("department"),
                "profile_image_url": d.get("profile_image_url"), "hire_date": d.get("hire_date"),
                "work_location_type": d.get("work_location_type")}
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

    status = doc.get("onboarding_status") or {}
    subject = status.get("email_subject")
    body_text = status.get("email_body")
    if not subject or not body_text:
        draft = draft_welcome_email(doc["full_name"], doc["job_title"], doc["department"], doc["work_email"], "")
        subject, body_text = draft["subject"], draft["body"]
    token = status.get("confirm_token")
    if not token:
        token = secrets.token_urlsafe(24)
        users.update_one({"employee_id": employee_id}, {"$set": {"onboarding_status.confirm_token": token}})
    base_url = PUBLIC_BASE_URL or request.host_url.rstrip("/")
    orientation = bookings.find_one({"employee_id": employee_id, "session_type": "orientation"},
                                    sort=[("date", 1), ("start_time", 1)])
    try:
        send_email(
            to_email=doc["personal_email"],
            subject=subject,
            html_body=_welcome_email_html(body_text, f"{base_url}/api/onboarding/confirm/{token}",
                                          _orientation_email_block(orientation), _credentials_email_block(doc)),
        )
    except Exception as exc:
        return jsonify({"message": f"Could not send email: {exc}"}), 502

    return jsonify({"message": f"Welcome email sent to {doc['personal_email']}."}), 200


def _store_profile_photo(employee_doc, file, ext):
    """Saves a profile photo under a NEW file name each time (employee id +
    a timestamp). Re-using one name per employee meant the browser kept
    showing the previously cached picture after a replace, so the edit
    looked like it hadn't worked. The previous file is removed. Returns the
    public path to store on the employee record."""
    employee_id = employee_doc["employee_id"]
    stamp = int(datetime.now(timezone.utc).timestamp())
    filename = secure_filename(f"{employee_id}-{stamp}.{ext}")
    file.save(os.path.join(UPLOAD_FOLDER, filename))

    old = employee_doc.get("profile_image_url") or ""
    old_name = os.path.basename(old)
    if old.startswith("/uploads/") and old_name and old_name != filename:
        try:
            os.remove(os.path.join(UPLOAD_FOLDER, old_name))
        except OSError:
            pass
    return f"/uploads/{filename}"


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

    profile_image_url = _store_profile_photo(doc, file, ext)
    _set_profile_photo_url(employee_id, profile_image_url)

    return jsonify({"message": "Photo uploaded.", "profile_image_url": profile_image_url}), 200


def _set_profile_photo_url(employee_id, url):
    """Records the employee's photo AND refreshes the copy kept on any
    equipment assigned to them (IT's product list shows it) - otherwise that
    copy points at the old, deleted file and the photo looks broken there."""
    users.update_one({"employee_id": employee_id}, {"$set": {"profile_image_url": url}})
    equipment.update_many({"assigned_to_employee_id": employee_id},
                          {"$set": {"assigned_to_employee_photo_url": url}})


def _remove_profile_photo(employee_doc):
    """Deletes the photo file and clears the field, so the employee shows
    initials everywhere (directory, requests, shipments, schedule...) - all
    of those read profile_image_url from the one employee record."""
    url = employee_doc.get("profile_image_url") or ""
    name = os.path.basename(url)
    if url.startswith("/uploads/") and name:
        try:
            os.remove(os.path.join(UPLOAD_FOLDER, name))
        except OSError:
            pass
    _set_profile_photo_url(employee_doc["employee_id"], None)


@app.delete("/api/employees/<employee_id>/photo")
@require_hr
def delete_employee_photo(employee_id):
    doc = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not doc:
        return jsonify({"message": "Employee not found."}), 404
    _remove_profile_photo(doc)
    return jsonify({"message": "Photo removed."}), 200


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
    out = _employee_public_view(doc)
    # HR-only: the temporary password HR handed out, so the Edit page can show
    # (and change) it. Gone (None) once the employee has made their own.
    out["temporary_password"] = doc.get("initial_password")
    return jsonify(out), 200


@app.put("/api/employees/<employee_id>")
@require_hr
def update_employee(employee_id):
    doc = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not doc:
        return jsonify({"message": "Employee not found."}), 404

    body = request.get_json(silent=True) or {}
    reset_password = body.pop("reset_password", False)
    typed_password = (body.pop("new_password", None) or "").strip()
    if typed_password and not 8 <= len(typed_password) <= 64:
        return jsonify({"message": "The password must be between 8 and 64 characters."}), 400

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

    new_password = None
    if reset_password or typed_password:
        new_password = typed_password or _generate_initial_password()
        updates["password_hash"] = bcrypt.hashpw(new_password.encode("utf-8"), bcrypt.gensalt())
        updates["initial_password"] = new_password
        updates["password_changed_at"] = None  # back on a temporary password
        # Same rule as a new hire: once onboarding has started, a temporary
        # password must be replaced at the next sign-in.
        updates["must_change_password"] = bool((doc.get("onboarding_status") or {}).get("started"))

    updates["updated_by"] = g.current_user["email"]
    updates["updated_at"] = datetime.now(timezone.utc).isoformat()

    users.update_one({"employee_id": employee_id}, {"$set": updates})
    out = {"message": "Employee updated."}
    if new_password:
        out["temporary_password"] = new_password  # shown once to HR to pass on
    return jsonify(out), 200


@app.delete("/api/employees/<employee_id>")
@require_hr
def delete_employee(employee_id):
    body = request.get_json(silent=True) or {}
    if body.get("confirm_employee_id") != employee_id:
        return jsonify({"message": "Confirmation ID did not match. Nothing was deleted."}), 400

    result = users.delete_one({"employee_id": employee_id, "role": "employee"})
    if result.deleted_count == 0:
        return jsonify({"message": "Employee not found."}), 404
    _clear_flow_items(employee_id)  # their uploaded documents go with them

    return jsonify({"message": "Employee deleted."}), 200


# ---------- Onboarding ----------
# A deliberately separate, HR-triggered workflow — Employees/registration
# does not auto-start this. HR picks a registered employee on the
# Onboarding tab, reviews an AI-drafted (or template) welcome email, sends
# it, and tracks progress via the confirm link the employee clicks plus one
# manually-marked step (orientation, as a fallback if auto-booking finds no
# free slot). IT equipment readiness is NOT manual — see
# _compute_it_equipment_ready below.

ONBOARDING_MANUAL_STEPS = {"orientation_scheduled"}


def _default_onboarding_status():
    return {
        "started": False, "started_at": None, "started_by": None,
        "welcome_email_sent": False, "welcome_email_sent_at": None,
        "email_subject": None, "email_body": None, "confirm_token": None,
        "email_confirmed": False, "email_confirmed_at": None,
        "it_equipment_ready": False, "it_equipment_ready_at": None,
        "orientation_scheduled": False, "orientation_scheduled_at": None,
    }


def _compute_it_equipment_ready(employee_doc):
    """Whether this employee's requested equipment has actually been
    handed over by IT — computed live from real equipment assignment
    records instead of a manual flag someone has to remember to tick, so
    it can never drift out of sync with what IT actually did. "Ready"
    means at least as many items are currently assigned to them as they
    asked for; employees who didn't request equipment are trivially ready."""
    _items, _extra, ready, ready_at = _equipment_fulfilment(employee_doc)
    return ready, ready_at


def _asset_card(e):
    """What IT's request cards show for one piece of equipment: its photo
    and how to find it (asset tag / serial number, the equipment id)."""
    return {"equipment_id": str(e["_id"]), "name": e.get("name"), "type": e.get("type"),
            "asset_tag": e.get("asset_tag") or "", "serial_number": e.get("serial_number") or "",
            "photo_url": e.get("photo_url")}


def _equipment_fulfilment(employee_doc):
    """Matches what the employee was approved for against what IT has
    actually assigned to them, item by item (by equipment type). This is
    the single source of truth for "is the equipment done?" - IT has no
    manual "done" button, so it can't be claimed without really assigning.
    Returns (items, extra_assigned, ready, ready_at): items is one entry
    per requested piece with the asset that satisfies it (or None)."""
    needed = [str(n).strip() for n in (employee_doc.get("equipment_needed") or []) if str(n).strip()]
    assigned = list(equipment.find({
        "assigned_to_employee_id": employee_doc["employee_id"], "status": "assigned",
    }))
    pool = list(assigned)
    items = []
    for need in needed:
        match = next((a for a in pool if (a.get("type") or "").strip().lower() == need.lower()), None)
        if match is not None:
            pool.remove(match)
        items.append({
            "type": need,
            "assigned": match is not None,
            "asset": ({**_asset_card(match), "assigned_date": match.get("assigned_date")} if match else None),
        })
    extra = [_asset_card(a) for a in pool]
    ready = all(i["assigned"] for i in items)
    ready_at = max((a["assigned_date"] for a in assigned if a.get("assigned_date")), default=None) \
        if ready and assigned else None
    return items, extra, ready, ready_at


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
            "profile_image_url": d.get("profile_image_url"),
            "hire_date": d.get("hire_date"),
            "work_location_type": d.get("work_location_type"),
            "onboarding_started": status.get("started", False),
        })
    return jsonify({"candidates": out}), 200


@app.get("/api/onboarding/active")
@require_hr
def onboarding_active_list():
    """Bird's-eye view of every employee currently onboarding, with their
    real progress - the thing the Onboarding tab was missing: before this,
    HR could only see one employee's progress at a time via the picker."""
    docs = users.find({"role": "employee", "onboarding_status.started": True})
    out = []
    for d in docs:
        _items, progress_percent = _onboarding_checklist(d)
        status = d.get("onboarding_status") or {}
        out.append({
            "employee_id": d["employee_id"],
            "full_name": d["full_name"],
            "department": d.get("department"),
            "job_title": d.get("job_title"),
            "profile_image_url": d.get("profile_image_url"),
            "started_at": status.get("started_at"),
            "progress_percent": progress_percent,
            "completed": bool(status.get("completed")),
            "completed_at": status.get("completed_at"),
        })
    out.sort(key=lambda e: e["started_at"] or "", reverse=True)
    return jsonify({"employees": out}), 200


def _generate_initial_password(length=12):
    """Random password meeting typical Microsoft complexity rules (upper,
    lower, digit, symbol). Ambiguous characters left out so it can be read
    out or typed without mistakes."""
    upper, lower, digits, symbols = "ABCDEFGHJKLMNPQRSTUVWXYZ", "abcdefghijkmnpqrstuvwxyz", "23456789", "!@#$%&*?"
    chars = [secrets.choice(upper), secrets.choice(lower), secrets.choice(digits), secrets.choice(symbols)]
    chars += [secrets.choice(upper + lower + digits + symbols) for _ in range(length - 4)]
    secrets.SystemRandom().shuffle(chars)
    return "".join(chars)


def _close_open_requests(employee_id, new_status=None):
    """Removes any still-open equipment request for this employee (when
    onboarding is cancelled or restarted) - including its stored one-time
    password. Cancelled requests are deleted rather than kept around, so
    IT only ever sees requests that are actually live."""
    messages.delete_many(
        {"employee_id": employee_id, "kind": "equipment_request", "request_status": "open"},
    )


# ---------- Flow-driven onboarding ----------
#
# Onboarding follows the employee's flow chart, in the order shown, but never
# holds up a step because an earlier one is still open. Each step is "done"
# when its real-world condition is met (the email was sent, IT assigned the
# equipment, ...). Steps SELMS performs itself ("Schedule orientation", and
# the "tell IT" part of "Prepare IT equipment") run straight away, in flow order; the rest are handed to
# their owner (HR sends the email, IT assigns equipment / creates the
# shipment, HR ticks off any custom step) and show as pending while the flow
# carries on past them.
#
# _advance_onboarding is idempotent and is called whenever something that
# could unblock the next step happens (email sent, equipment assigned,
# shipment saved, a step ticked off).

END_ONBOARDING = "Complete onboarding"
END_OFFBOARDING = "Complete offboarding"
ONBOARDING_AUTO_STEPS = ("Schedule orientation", END_ONBOARDING)


def _flow_step_nodes(employee_id):
    """The flow's steps in order, minus the trigger."""
    return [n for n in _employee_flow_nodes(employee_id) if n.get("id") != "trigger"]


def _flow_step_kind(node):
    label = node.get("label")
    if node.get("step") in ("notification", "email"):
        return "auto"      # SELMS sends it when it is due
    if node.get("step") in EMPLOYEE_STEP_TYPES:
        return "employee"  # the employee does it (documents / survey)
    if label in ONBOARDING_AUTO_STEPS:
        return "auto"      # SELMS does it when reached
    if label in ("Prepare IT equipment", "Arrange courier"):
        return "it"        # IT does it, SELMS watches for the result
    return "hr"            # HR does it (send the email, tick off a custom step)


def _flow_step_done(emp, node):
    if node.get("step") == "email":
        return bool((((emp.get("onboarding_status") or {}).get("email_steps") or {}).get(node.get("id")) or {}).get("done_at"))
    if node.get("step") == "notification":
        return node.get("id") in ((emp.get("onboarding_status") or {}).get("notification_steps") or {})
    if node.get("step") in EMPLOYEE_STEP_TYPES:
        return _custom_step_done(emp, node, "onboarding")
    status = emp.get("onboarding_status") or {}
    label = node.get("label")
    if label == "Send welcome email":
        return bool(status.get("welcome_email_sent"))
    if label == "Prepare IT equipment":
        return _equipment_fulfilment(emp)[2]
    if label == "Arrange courier":
        return bool(shipments.find_one({
            "employee_id": emp["employee_id"], "direction": "to_employee",
            "status": {"$in": ["order_created", "dropped_off", "delivered"]},
        }))
    if label == "Schedule orientation":
        return bool(status.get("orientation_scheduled"))
    if label == END_ONBOARDING:
        return bool(status.get("completed"))
    return node.get("id") in (status.get("manual_steps") or {})


def _flow_step_hint(emp, node):
    if node.get("step") == "email":
        cfg = node.get("email") or {}
        err = ((((emp.get("onboarding_status") or {}).get("email_steps") or {}).get(node.get("id")) or {}).get("error"))
        return (f"SELMS emails {_email_step_recipients_text(cfg)}: \"{cfg.get('subject') or ''}\"."
                + (f" Last try failed: {err}" if err else ""))
    if node.get("step") == "notification":
        return f"SELMS sends this notification to {_notification_recipients_text(node.get('notify') or {})}."
    if node.get("step") in EMPLOYEE_STEP_TYPES:
        return _custom_step_hint(emp, node, "onboarding")
    label = node.get("label")
    if label == "Send welcome email":
        if (emp.get("onboarding_status") or {}).get("email_saved"):
            return "Saved. SELMS sends it when this step comes due."
        return "HR reviews and saves the welcome email. SELMS sends it when this step comes due."
    if label == "Prepare IT equipment":
        items, _extra, _ready, _at = _equipment_fulfilment(emp)
        done = sum(1 for i in items if i["assigned"])
        told = (emp.get("onboarding_status") or {}).get("it_notified")
        if not told:
            return f"SELMS will tell IT. Waiting for IT to assign the equipment ({done} of {len(items)})."
        return "IT has been told. " + (_it_progress_text(emp, "equipment_request") or "IT has done everything.")
    if label == "Arrange courier":
        return "Waiting for IT to create the Pos shipment."
    if label == "Schedule orientation":
        return "SELMS books the next free slot."
    if label == END_ONBOARDING:
        return "Done by itself once every step above is finished."
    return "Tick this off when it's been done."


def _onboarding_run(emp):
    """Per-step state for the flow chart: "done", or "current" for every
    step still open (steps don't wait on each other)."""
    steps = []
    for node in _flow_step_nodes(emp["employee_id"]):
        state = "done" if _flow_step_done(emp, node) else "current"
        steps.append({
            "id": node["id"], "label": node.get("label"),
            "kind": _flow_step_kind(node),
            "state": state,
            "hint": _timed_hint(emp, node, "onboarding", _flow_step_hint(emp, node)) if state == "current" else None,
            **_timing_fields(emp, node, "onboarding", state),
        })
    return steps


def _notify_it_equipment_request(emp):
    """Creates IT's equipment request (replacing any earlier open one for
    this person) and records that IT has been notified."""
    now = datetime.now(timezone.utc).isoformat()
    _close_open_requests(emp["employee_id"])
    equipment_needed = emp.get("equipment_needed") or []
    equipment_line = ", ".join(equipment_needed) if equipment_needed else "none listed"
    messages.insert_one({
        "employee_id": emp["employee_id"],
        "employee_name": emp["full_name"],
        "target_role": "it",
        "sender_role": "system",
        "sender_name": "SELMS System",
        # Short on purpose - the full detail lives on the structured request
        # card in IT's Requests tab (GET /api/it/requests).
        "content": f"New equipment request for {emp['full_name']}: {equipment_line}.",
        "kind": "equipment_request",
        "request_status": "open",
        # One-time password IT uses to create the employee's Microsoft
        # account (the SELMS login password is only stored hashed).
        "provisioning": {"initial_password": _generate_initial_password()},
        "created_at": now,
    })
    users.update_one({"employee_id": emp["employee_id"]}, {"$set": {
        "onboarding_status.it_notified": True, "onboarding_status.it_notified_at": now,
    }})
    _notify("it", None, "notification", f"New equipment request: {emp['full_name']}",
            f"Needs: {equipment_line}.", {"type": "requests"})


def _aimed_note(not_before, slot):
    """"" when an automatic booking landed exactly where the step's timing
    aimed it; otherwise a short note such as "2:00 PM on 24 Oct wasn't free"."""
    if not isinstance(not_before, datetime) or not slot:
        return ""
    aimed = not_before.astimezone(MY_TZ)
    if slot["date"] == aimed.date().isoformat() and (
            (aimed.hour, aimed.minute) == (0, 0) or slot["start_time"] == aimed.strftime("%H:%M")):
        return ""  # same day (no time set) or exactly the time chosen
    return f"{_at_text(aimed)} wasn't available"


def _tell_hr_if_moved(emp, what, note, slot):
    """HR's Smart Schedule notice for an automatic booking: where it landed,
    and why if it isn't the time the step aimed for."""
    when = _clock_text(slot["date"], slot["start_time"])
    if note:
        _notify("hr", None, "notification", f"{what} moved: {emp.get('full_name')}",
                f"{note}, so it's booked for {when}.", {"type": "schedule"})
    else:
        _notify("hr", None, "notification", f"{what} booked: {emp.get('full_name')}",
                f"Booked for {when}.", {"type": "schedule"})


def _default_meeting_mode(emp):
    """Orientation / exit interview format when HR hasn't picked one with the
    pencil: remote employees meet online (Google Meet link + invitation),
    onsite employees in person."""
    return "online" if (emp or {}).get("work_location_type") in SHIPPING_WORK_LOCATIONS else "in_person"


def _plan_fields(emp, plan, session_type, fallback_mode):
    """Booking fields from what HR planned on the orientation / exit interview
    step (node["meeting"] = {mode, title, location, meeting_url, attendee_ids}):
    the session name, place, format, link and who else is invited. Anything
    not planned falls back to the defaults."""
    plan = plan or {}
    mode = plan.get("mode") if plan.get("mode") in MEETING_MODES else fallback_mode
    attendees, seen = [], set()
    for pid in [emp["employee_id"], *(plan.get("attendee_ids") or [])]:
        person = _find_person(str(pid)) if pid and pid not in seen else None
        if person:
            seen.add(pid)
            attendees.append(_person_ref(person))
    return {
        "title": (plan.get("title") or "").strip() or SESSION_TYPES[session_type],
        "location": (plan.get("location") or "").strip(),
        "mode": mode,
        "meeting_url": (plan.get("meeting_url") or "").strip() if mode == "online" else "",
        "attendees": attendees,
    }


def _book_orientation(emp, not_before=None, plan=None):
    """Books the next free slot in the format planned on the step (or the one
    chosen when onboarding started), creating the Meet link for online.
    Returns (slot_or_None, warning)."""
    status = emp.get("onboarding_status") or {}
    fields = _plan_fields(emp, plan, "orientation", _default_meeting_mode(emp))
    mode = fields["mode"]
    if mode not in MEETING_MODES:
        mode = "in_person"
    slot = _find_next_available_slot(DEFAULT_SESSION_MINUTES, not_before=not_before)
    if slot is None and not_before:
        slot = _find_next_available_slot(DEFAULT_SESSION_MINUTES)  # nothing free on/after that day: earliest instead
    if slot is None:
        return None, "No free orientation slot in the next 14 days - book one from Smart Schedule."

    now = datetime.now(timezone.utc).isoformat()
    booking = {
        "employee_id": emp["employee_id"],
        "employee_name": emp["full_name"],
        "session_type": "orientation",
        "date": slot["date"],
        "start_time": slot["start_time"],
        "duration_minutes": slot["duration_minutes"],
        **fields,
        "created_at": now,
        "aimed_note": _aimed_note(not_before, slot),
    }
    extra, warning = _provision_meeting(booking)
    booking.update(extra)
    bookings.insert_one(booking)
    users.update_one({"employee_id": emp["employee_id"]}, {"$set": {
        "onboarding_status.orientation_scheduled": True,
        "onboarding_status.orientation_scheduled_at": now,
    }})
    fmt = "online" if mode == "online" else "in person"
    _notify("employee", emp["employee_id"], "notification", "Orientation scheduled",
            f"Your orientation is on {_clock_text(slot['date'], slot['start_time'])} ({fmt}).",
            {"type": "onboarding"})
    _tell_hr_if_moved(emp, "Orientation", booking["aimed_note"], slot)
    return {**slot, "mode": mode, "meeting_url": booking["meeting_url"]}, warning


def _advance_onboarding(employee_id):
    """Runs the whole flow in order: performs SELMS's own steps as they come
    up and passes over the ones that need a person - those don't hold the
    rest of the flow back. Safe to call any time - does nothing if
    onboarding hasn't been started, and steps already done are skipped."""
    summary = {"it_notified": False, "orientation": None, "warning": None}
    welcome_due = False
    for node in _flow_step_nodes(employee_id):
        emp = users.find_one({"employee_id": employee_id, "role": "employee"})
        if not emp or not (emp.get("onboarding_status") or {}).get("started"):
            return summary
        label = node.get("label")
        # "Prepare IT equipment" starts by telling IT - once, even if no equipment is
        # listed (IT still needs the account details).
        if (label == "Prepare IT equipment" and not (emp.get("onboarding_status") or {}).get("it_notified")
                and _step_is_due(emp, node, "onboarding")):
            _notify_it_equipment_request(emp)
            summary["it_notified"] = True
            emp = users.find_one({"employee_id": employee_id, "role": "employee"}) or emp
        if _flow_step_done(emp, node):
            continue
        if label == "Send welcome email":
            st = emp.get("onboarding_status") or {}
            if st.get("email_saved") and st.get("email_subject") and st.get("email_body") \
                    and _step_is_due(emp, node, "onboarding"):
                welcome_due = True  # sent after this run - see below
            continue
        if node.get("step") == "email":
            if _step_is_due(emp, node, "onboarding"):
                _send_email_step(emp, node, "onboarding")
            continue
        if node.get("step") == "notification":
            if _step_is_due(emp, node, "onboarding"):
                _send_notification_step(emp, node, "onboarding")
            continue
        if node.get("step") in EMPLOYEE_STEP_TYPES:
            if _step_is_due(emp, node, "onboarding"):
                _issue_flow_step(emp, node, "onboarding")
            continue
        if label == "Schedule orientation":
            slot, warning = _book_orientation(emp, not_before=_step_target_at(emp, node, "onboarding"), plan=node.get("meeting"))
            summary["warning"] = warning
            if slot is not None:
                summary["orientation"] = slot
        # any other step is done by a person - the flow carries on past it
    if welcome_due:
        # Last, so the email's "Your orientation" box (time, format and the
        # Google Meet "Join online" link) shows the session just booked above.
        emp = users.find_one({"employee_id": employee_id, "role": "employee"})
        st = (emp or {}).get("onboarding_status") or {}
        if emp and not st.get("welcome_email_sent"):
            _send_welcome_email(emp, st["email_subject"], st["email_body"], st.get("started_by") or "SELMS",
                                advance=False)
    summary["completed"] = _check_completion(employee_id, "onboarding")
    return summary


def _advance_safely(employee_id):
    """For hooks inside other routes - advancing the flow must never make
    the action that triggered it fail."""
    try:
        _advance_onboarding(employee_id)
    except Exception as exc:  # noqa: BLE001
        print(f"[onboarding flow] could not advance {employee_id}: {exc}")


MEETING_STEPS = {"onboarding": ("Schedule orientation", "orientation"),
                 "offboarding": ("Schedule exit interview", "exit_interview")}


@app.post("/api/<process>/<employee_id>/meeting/rebook")
@require_hr
def rebook_flow_meeting(process, employee_id):
    """HR saved new plans on the orientation / exit interview step after the
    process had started: the booked meeting is replaced by one that follows
    the step's timing and format (first free slot from then, clash-free).
    Before Start there is nothing to move - the plan is just saved."""
    if process not in MEETING_STEPS:
        return jsonify({"message": "Unknown process."}), 404
    emp = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not emp:
        return jsonify({"message": "Employee not found."}), 404
    if not (emp.get(f"{process}_status") or {}).get("started"):
        return jsonify({"message": "Saved. SELMS books it when you press Start.", "booked": None}), 200
    label, session_type = MEETING_STEPS[process]
    nodes = _flow_step_nodes(employee_id) if process == "onboarding" else _offboarding_step_nodes(employee_id)
    node = next((n for n in nodes if n.get("label") == label), None)
    if node is None:
        return jsonify({"message": f"This flow has no '{label}' step."}), 400

    _delete_booking_docs({"employee_id": employee_id, "session_type": session_type})
    flag = "orientation_scheduled" if process == "onboarding" else "exit_interview_scheduled"
    users.update_one({"employee_id": employee_id}, {"$set": {
        f"{process}_status.{flag}": False, f"{process}_status.{flag}_at": None}})
    fresh = users.find_one({"employee_id": employee_id})
    book = _book_orientation if process == "onboarding" else _book_exit_interview
    slot, warning = book(fresh, not_before=_step_target_at(fresh, node, process), plan=node.get("meeting"))
    _advance_flow(employee_id, process)
    if slot is None:
        return jsonify({"message": warning or "No free slot found - book one from Smart Schedule.", "booked": None}), 200
    text = f"Moved to {_clock_text(slot['date'], slot['start_time'])}."
    return jsonify({"message": text + (f" {warning}" if warning else ""), "booked": slot}), 200


# ---------- Review before Start ----------
#
# Pressing Start first shows HR every step of this employee's flow, in
# order, with what it will do - the email text, the documents, what IT is
# asked for, the meeting plan, the survey questions, HR's own "+" steps.
# Nothing runs here; Start only happens when HR confirms the review.

def _item_text(e):
    tag = e.get("asset_tag") or ""
    return f"{e.get('name') or e.get('type') or 'Item'}{f' ({tag})' if tag else ''}"


def _review_when(emp, node, process):
    target = _step_target_at(emp, node, process)
    if target:
        return f"On {_at_text(target)}"
    return "Straight away when you confirm"


def _review_step(emp, node, process):
    label = node.get("label") or ""
    step = node.get("step")
    kind = _timing_kind(node, process)
    st = emp.get(f"{process}_status") or {}
    out = {"id": node.get("id"), "label": label, "locked": bool(node.get("locked")), "lines": [],
           "when": _review_when(emp, node, process) if kind else None}
    lines = out["lines"]
    if label in ("Send welcome email", "Send offboarding email"):
        out["email"] = True  # the email itself is sent alongside, editable in the review
        lines.append(f"To: {emp.get('personal_email') or emp.get('work_email')}")
    elif step == "documents":
        docs = node.get("docs") or []
        if not docs:
            lines.append("No documents added - nothing will be sent.")
        for d in docs:
            what = "download and upload back (HR approves)" if d.get("action") == "upload" else "download only"
            lines.append(f"{d.get('title') or 'Document'} - {what}{' (file attached)' if d.get('file_id') else ''}")
    elif step == "survey":
        sv = node.get("survey") or {}
        types = {"rating": "rating 1-5", "yes_no": "yes / no", "text": "written answer"}
        lines.append(f"Survey: {sv.get('title') or label}")
        for i, q in enumerate(sv.get("questions") or [], 1):
            lines.append(f"{i}. {q.get('text')} ({types.get(q.get('type'), q.get('type'))})")
    elif step == "email":
        cfg = node.get("email") or {}
        lines.append(f"To: {_email_step_recipients_text(cfg)}")
        lines.append(f"Subject: {cfg.get('subject') or '(no subject)'}")
        if cfg.get("message"):
            lines.append(_render_notification_text(cfg.get("message"), emp)[:300])
    elif step == "notification":
        cfg = node.get("notify") or {}
        lines.append(f"To: {_notification_recipients_text(cfg)} (bell notification)")
        lines.append(f"{_render_notification_text(cfg.get('title'), emp)}: {_render_notification_text(cfg.get('message'), emp)}"[:300])
    elif label == "Prepare IT equipment":
        needed = [str(n) for n in (emp.get("equipment_needed") or []) if str(n).strip()]
        lines.append("IT is asked to prepare: " + (", ".join(needed) if needed else "nothing requested"))
    elif label == "Arrange courier":
        addr = ", ".join(x for x in (emp.get("address_line"), emp.get("postcode"), emp.get("state")) if x)
        lines.append(f"IT posts the equipment with Pos Malaysia to: {addr or 'the address on file'}")
    elif label == "Retrieve IT equipment":
        items = list(equipment.find({"assigned_to_employee_id": emp["employee_id"], "status": "assigned"}))
        lines.append("IT is asked to collect: " + (", ".join(_item_text(e) for e in items) if items else "nothing is assigned"))
        if emp.get("work_location_type") in SHIPPING_WORK_LOCATIONS:
            lines.append("Remote: the employee posts it back with Pos Malaysia.")
    elif label in ("Schedule orientation", "Schedule exit interview"):
        plan = node.get("meeting") or {}
        chosen = plan.get("mode") if plan.get("mode") in MEETING_MODES else _default_meeting_mode(emp)
        mode = "Online (Google Meet link)" if chosen == "online" else "In person"
        target = _step_target_at(emp, node, process)
        lines.append(f"Planned: {_at_text(target) if target else 'the first free slot after you confirm'} · {mode}")
        if plan.get("location"):
            lines.append(f"Location: {plan['location']}")
        others = [a.get("name") for a in (plan.get("attendees") or []) if a.get("name")]
        if others:
            lines.append(f"Also invited: {', '.join(others)}")
        if process == "offboarding" and st.get("last_working_day"):
            lines.append(f"On or before the last working day ({st['last_working_day']}).")
    elif label in (END_ONBOARDING, END_OFFBOARDING):
        lines.append("Finishes by itself once every step above is done.")
        if process == "offboarding":
            lines.append("The employee's SELMS login closes the day after their last working day.")
    elif node.get("icon") == "ti-calendar":
        lines.append("HR books this meeting with the pencil on the step.")
    else:
        lines.append("HR does this step and marks it done.")
    return out


@app.get("/api/<process>/<employee_id>/review")
@require_hr
def review_before_start(process, employee_id):
    """Everything Start will do, step by step - read only."""
    if process not in ("onboarding", "offboarding"):
        return jsonify({"message": "Unknown process."}), 404
    emp = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not emp:
        return jsonify({"message": "Employee not found."}), 404
    st = emp.get(f"{process}_status") or {}
    if st.get("started"):
        return jsonify({"message": f"{process.capitalize()} has already started."}), 400
    if process == "offboarding" and not st.get("last_working_day"):
        return jsonify({"message": "Set the departure details first."}), 400
    if process == "onboarding":
        _ensure_temp_password(employee_id)  # the welcome email shows the sign-in details
        emp = users.find_one({"employee_id": employee_id, "role": "employee"}) or emp
        nodes = _flow_step_nodes(employee_id)
    else:
        nodes = _offboarding_step_nodes(employee_id)
    steps = [_review_step(emp, n, process) for n in nodes]
    email = None
    if any(s.get("email") for s in steps):
        if st.get("email_saved") and st.get("email_subject") and st.get("email_body"):
            email = {"subject": st["email_subject"], "body": st["email_body"], "saved": True}
        elif process == "onboarding":
            draft = draft_welcome_email(emp["full_name"], emp.get("job_title") or "", emp.get("department") or "",
                                        emp.get("work_email") or "", "")
            email = {"subject": draft["subject"], "body": _with_sign_in(draft["body"], emp), "saved": False}
        else:
            email = {**draft_offboarding_email(emp), "saved": False}
    return jsonify({
        "process": process,
        "employee": {"employee_id": emp["employee_id"], "full_name": emp.get("full_name"),
                     "department": emp.get("department"), "profile_image_url": emp.get("profile_image_url"),
                     "hire_date": emp.get("hire_date"), "work_location_type": emp.get("work_location_type")},
        "departure": ({"departure_type": st.get("departure_type"), "last_working_day": st.get("last_working_day"),
                       "notes": st.get("notes")} if process == "offboarding" else None),
        "email": email,
        "steps": steps,
    }), 200


@app.post("/api/onboarding/<employee_id>/auto-start")
@require_hr
def onboarding_auto_start(employee_id):
    """Starts onboarding. Marks it started and runs the flow from its first
    step: if that's the welcome email, an AI draft comes back for HR to
    review and send (nothing reaches the new hire without a human looking at
    it); the steps after it only run as each one is completed."""
    doc = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not doc:
        return jsonify({"message": "Employee not found."}), 404

    mode = (request.get_json(silent=True) or {}).get("mode") or "in_person"
    if mode not in MEETING_MODES:
        mode = "in_person"

    now = datetime.now(timezone.utc).isoformat()
    updates = {
        "onboarding_status.started": True,
        "onboarding_status.started_by": g.current_user["email"],
        "onboarding_status.orientation_mode": mode,
    }
    if not (doc.get("onboarding_status") or {}).get("started"):
        updates["onboarding_status.started_at"] = now
    users.update_one({"employee_id": employee_id}, {"$set": updates})
    _ensure_temp_password(employee_id)
    _require_password_reset(employee_id)

    # Only draft the email if the welcome-email step is still to be done.
    draft = {"subject": "", "body": ""}
    fresh = users.find_one({"employee_id": employee_id})
    email_node = next((n for n in _flow_step_nodes(employee_id) if n.get("label") == "Send welcome email"), None)
    if email_node is not None and not _flow_step_done(fresh, email_node) \
            and not (fresh.get("onboarding_status") or {}).get("email_saved"):
        draft = draft_welcome_email(
            doc["full_name"], doc["job_title"], doc["department"], doc["work_email"], "",
        )
        draft["body"] = _with_sign_in(draft["body"], fresh)

    summary = _advance_onboarding(employee_id)
    fresh = users.find_one({"employee_id": employee_id})
    run = _onboarding_run(fresh)
    current = next((s for s in run if s["state"] == "current"), None)

    return jsonify({
        "subject": draft["subject"],
        "body": draft["body"],
        "orientation": summary["orientation"],   # set only if the flow reached and ran that step
        "meeting_warning": summary["warning"],
        "schedule_enabled": True,
        "it_notified": summary["it_notified"],
        "email_sent": bool((fresh.get("onboarding_status") or {}).get("welcome_email_sent")),
        "current_step": current["label"] if current else None,
        "steps": run,
    }), 200


@app.get("/api/onboarding/<employee_id>/run")
@require_hr
def onboarding_run(employee_id):
    """Where this employee is in their flow: every step with its state."""
    emp = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not emp:
        return jsonify({"message": "Employee not found."}), 404
    started = bool((emp.get("onboarding_status") or {}).get("started"))
    return jsonify({"started": started, "steps": _onboarding_run(emp) if started else []}), 200


@app.post("/api/onboarding/<employee_id>/complete-step")
@require_hr
def onboarding_complete_step(employee_id):
    """HR ticking off a step that only a person can complete (a custom step
    they added to the flow). Only a step that's still open can be completed."""
    emp = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not emp:
        return jsonify({"message": "Employee not found."}), 404
    if not (emp.get("onboarding_status") or {}).get("started"):
        return jsonify({"message": "Onboarding hasn't been started."}), 400

    step_id = (request.get_json(silent=True) or {}).get("step_id")
    run = _onboarding_run(emp)
    current = next((s for s in run if s["state"] == "current" and s["id"] == step_id), None)
    if not current:
        return jsonify({"message": "That step isn't open."}), 400
    if current["kind"] != "hr" or current["label"] == "Send welcome email":
        return jsonify({"message": "This step completes by itself when its work is done."}), 400

    users.update_one({"employee_id": employee_id}, {"$set": {
        f"onboarding_status.manual_steps.{step_id}": datetime.now(timezone.utc).isoformat(),
    }})
    _advance_safely(employee_id)
    return jsonify({"message": "Step completed."}), 200


@app.post("/api/onboarding/<employee_id>/cancel")
@require_hr
def onboarding_cancel(employee_id):
    """Undo an accidental 'Start onboarding' — resets onboarding_status
    back to not-started and removes the auto-booked orientation. Two
    things it deliberately does NOT try to undo, because they're
    real-world actions outside the database: an already-sent welcome
    email (can't be recalled), and equipment IT has already physically
    assigned. Both are surfaced as warnings in the response instead of
    silently pretending to reverse them. If IT was already notified, they
    get a follow-up system message so they don't keep preparing equipment
    for someone who isn't onboarding after all."""
    doc = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not doc:
        return jsonify({"message": "Employee not found."}), 404

    status = doc.get("onboarding_status") or {}
    if not status.get("started"):
        return jsonify({"message": "Onboarding hasn't been started for this employee."}), 400

    warnings = []
    if status.get("welcome_email_sent"):
        warnings.append("The welcome email was already sent to the employee — this cannot be recalled.")

    # Assigned equipment and shipment records are removed below, but a
    # parcel that already left for Pos is physically out there.
    if shipments.count_documents({
        "employee_id": employee_id, "direction": "to_employee",
        "status": {"$in": ["dropped_off", "delivered"]},
    }):
        warnings.append("A parcel was already posted to this employee — the items may still be in transit.")

    _clear_flow_items(employee_id, "onboarding")
    users.update_one({"employee_id": employee_id}, {"$set": {
        "onboarding_status": _default_onboarding_status(),
        "must_change_password": False,
    }})
    removed_bookings = _delete_booking_docs({
        "employee_id": employee_id, "session_type": "orientation",
    })

    # Cancelling wipes everything tied to this onboarding straight away:
    # IT's request (and its one-time password), the equipment already
    # assigned to the hire (released back to Available) and any Pos
    # shipment records. Real chat between IT and the employee is untouched.
    _close_open_requests(employee_id)
    messages.delete_many({
        "employee_id": employee_id, "target_role": "it", "sender_role": "system",
    })

    released = []
    for item in list(equipment.find({"assigned_to_employee_id": employee_id, "status": "assigned"})):
        equipment.update_one({"_id": item["_id"]}, {"$set": {
            "status": "available",
            "assigned_to_employee_id": None,
            "assigned_to_employee_name": None,
            "assigned_to_employee_department": None,
            "assigned_to_employee_photo_url": None,
            "assigned_date": None,
            "assignment_notes": None,
            "last_returned_date": datetime.now(timezone.utc).isoformat(),
        }})
        released.append(item.get("name") or "equipment")

    removed_parcels = []
    for parcel in list(shipments.find({"employee_id": employee_id, "direction": "to_employee"})):
        qr = parcel.get("qr_image_url")
        if qr:
            try:
                os.remove(os.path.join(UPLOAD_FOLDER, os.path.basename(qr)))
            except OSError:
                pass
        shipments.delete_one({"_id": parcel["_id"]})
        removed_parcels.append(parcel.get("pos_reference") or "unreferenced parcel")

    # Only if IT had actually done real-world work does it need telling -
    # one short note saying what was undone, which IT can delete themselves.
    if released or removed_parcels:
        parts = []
        if released:
            parts.append("equipment released back to stock: " + ", ".join(released))
        if removed_parcels:
            parts.append("shipment record removed (Pos ref: " + ", ".join(removed_parcels) + ")")
        messages.insert_one({
            "employee_id": employee_id,
            "employee_name": doc["full_name"],
            "target_role": "it",
            "sender_role": "system",
            "sender_name": "SELMS System",
            "content": f"Onboarding for {doc['full_name']} was cancelled by HR — " + "; ".join(parts) + ".",
            "kind": "onboarding_cancelled",
            "created_at": datetime.now(timezone.utc).isoformat(),
        })

    return jsonify({
        "message": "Onboarding cancelled.",
        "warnings": warnings,
        "removed_bookings": removed_bookings,
        "released_equipment": released,
        "removed_shipments": len(removed_parcels),
        "it_notified_of_cancellation": bool(released or removed_parcels),
    }), 200


@app.post("/api/onboarding/<employee_id>/draft-email")
@require_hr
def onboarding_draft_email(employee_id):
    doc = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not doc:
        return jsonify({"message": "Employee not found."}), 404

    instruction = (request.get_json(silent=True) or {}).get("instruction", "")
    st = doc.get("onboarding_status") or {}
    if not instruction and st.get("email_saved") and st.get("email_subject") and st.get("email_body"):
        return jsonify({"subject": st["email_subject"], "body": st["email_body"], "saved": True,
                        "sent": bool(st.get("welcome_email_sent")), "started": bool(st.get("started"))}), 200
    if (doc.get("onboarding_status") or {}).get("started"):
        _ensure_temp_password(employee_id)  # so the email always has a password to show
        doc = users.find_one({"employee_id": employee_id, "role": "employee"}) or doc
    draft = draft_welcome_email(
        doc["full_name"], doc["job_title"], doc["department"], doc["work_email"], instruction,
    )
    draft["body"] = _with_sign_in(draft["body"], doc)
    return jsonify({**draft, "started": bool(st.get("started"))}), 200


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
    base_url = PUBLIC_BASE_URL or request.host_url.rstrip("/")
    confirm_url = f"{base_url}/api/onboarding/confirm/{token}"

    try:
        orientation = bookings.find_one(
            {"employee_id": employee_id, "session_type": "orientation"},
            sort=[("date", 1), ("start_time", 1)],
        )
        send_email(to_email=doc["personal_email"], subject=subject,
                    html_body=_welcome_email_html(body_text, confirm_url,
                                                  _orientation_email_block(orientation),
                                                  # already in the text HR reviewed? then don't repeat it
                                                  "" if "Your SELMS sign-in" in body_text
                                                  else _credentials_email_block(doc)))
    except Exception as exc:
        return jsonify({"message": f"Could not send email: {exc}"}), 502
    _require_password_reset(employee_id)

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

    _advance_safely(employee_id)
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
        _notify("hr", None, "notification", f"{doc['full_name']} confirmed the welcome email",
                "They clicked the confirm button.", {"type": "employee", "employee_id": doc["employee_id"]})

    return f"<h3>Thanks, {doc['full_name']} — confirmed. You can close this tab.</h3>", 200


@app.get("/api/onboarding/<employee_id>/status")
@require_hr
def onboarding_status(employee_id):
    doc = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not doc:
        return jsonify({"message": "Employee not found."}), 404
    status = dict(doc.get("onboarding_status") or _default_onboarding_status())
    status["it_equipment_ready"], status["it_equipment_ready_at"] = _compute_it_equipment_ready(doc)
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
    _advance_safely(employee_id)
    return jsonify({"message": "Updated."}), 200


def _hr_chat_snapshot():
    """A fresh read of real operational counts, handed to Claude as
    context so the HR chatbot's answers reflect what's actually in the
    database right now rather than being guessed."""
    onboarding_active = list(users.find({"role": "employee", "onboarding_status.started": True}))
    onboarding_pending_email = sum(
        1 for e in onboarding_active if not e.get("onboarding_status", {}).get("welcome_email_sent"))
    onboarding_pending_orientation = sum(
        1 for e in onboarding_active if not e.get("onboarding_status", {}).get("orientation_scheduled"))
    onboarding_pending_equipment = sum(
        1 for e in onboarding_active if not _compute_it_equipment_ready(e)[0])

    offboarding_active = list(users.find({"role": "employee", "offboarding_status.started": True}))
    offboarding_pending_exit_interview = sum(
        1 for e in offboarding_active if not e.get("offboarding_status", {}).get("exit_interview_scheduled"))
    offboarding_pending_access_revoke = sum(
        1 for e in offboarding_active if not e.get("offboarding_status", {}).get("access_revoked"))

    equip_total = equipment.count_documents({})
    equip_available = equipment.count_documents({"status": "available"})
    equip_assigned = equipment.count_documents({"status": "assigned"})
    equip_returned = equipment.count_documents({"status": "returned"})

    onboarding_names = [e["full_name"] for e in onboarding_active] or ["none"]
    offboarding_names = [e["full_name"] for e in offboarding_active] or ["none"]

    return (
        f"Active onboarding: {len(onboarding_active)} employee(s) - {onboarding_names}.\n"
        f"  Pending welcome email: {onboarding_pending_email}. "
        f"Pending orientation: {onboarding_pending_orientation}. "
        f"Pending equipment: {onboarding_pending_equipment}.\n"
        f"Active offboarding: {len(offboarding_active)} employee(s) - {offboarding_names}.\n"
        f"  Pending exit interview: {offboarding_pending_exit_interview}. "
        f"Pending access revocation: {offboarding_pending_access_revoke}.\n"
        f"Equipment - total: {equip_total}, available: {equip_available}, "
        f"assigned: {equip_assigned}, returned: {equip_returned}."
    )


@app.post("/api/hr/chat")
@require_hr
def hr_chat():
    body = request.get_json(silent=True) or {}
    message = (body.get("message") or "").strip()
    history = body.get("history") or []
    if not message:
        return jsonify({"message": "message is required."}), 400

    system_prompt = (
        "You are the SELMS Admin Assistant, helping an HR staff member inside the "
        "Smart Employee Lifecycle Management System. Answer only using the live "
        "system snapshot below or the lookup tools - never invent employee names, "
        "counts, or statuses that aren't in them. For any question about a specific "
        "person (who is EMP-004, their department, age, which onboarding step they "
        "are on) call the tools. If the tools and snapshot don't cover it, say you "
        "don't have that information rather than guessing. Keep answers short and "
        "direct.\n\nCurrent system snapshot:\n" + _hr_chat_snapshot()
    )
    anthropic_messages = [{"role": m["role"], "content": m["content"]}
                          for m in history if m.get("role") in ("user", "assistant")]
    anthropic_messages.append({"role": "user", "content": message})

    try:
        reply, docs = _chat_with_documents(system_prompt, anthropic_messages, HR_CHAT_TOOLS, _run_hr_tool)
    except Exception as exc:
        return jsonify({"message": f"Could not reach the assistant: {exc}"}), 502

    return jsonify({"reply": reply, "documents": docs}), 200


# ---------- Employee self-service ----------
#
# Everything an employee's own mobile session can see or do about
# themselves: profile, onboarding checklist, and signing the standard
# company documents. Always scoped to g.current_employee (set by
# require_employee from the JWT), never to an employee_id in the URL.

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

    profile_image_url = _store_profile_photo(g.current_employee, file, ext)
    _set_profile_photo_url(g.current_employee["employee_id"], profile_image_url)
    _advance_safely(g.current_employee["employee_id"])  # the photo may be the last item

    return jsonify({"message": "Photo uploaded.", "profile_image_url": profile_image_url}), 200


@app.delete("/api/employee/me/photo")
@require_employee
def employee_delete_own_photo():
    _remove_profile_photo(g.current_employee)
    return jsonify({"message": "Photo removed."}), 200


def _onboarding_checklist(employee_doc):
    """The 5-item onboarding checklist from the report (fig 3.28), derived
    from onboarding_status and signed_documents rather than duplicated
    into its own field — one source of truth for how far onboarding has
    progressed, whether HR, the employee, or the active-onboarding
    overview list is looking at it. Returns (items, progress_percent)."""
    status = employee_doc.get("onboarding_status") or _default_onboarding_status()
    has_photo = bool(employee_doc.get("profile_image_url"))
    given = list(flow_documents.find({"employee_id": employee_doc["employee_id"], "process": "onboarding"}))
    equipment_ready, equipment_ready_at = _compute_it_equipment_ready(employee_doc)
    orientation_booking = bookings.find_one(
        {"employee_id": employee_doc["employee_id"], "session_type": "orientation"},
        sort=[("date", 1), ("start_time", 1)],
    )
    # Remote hires get their equipment by post rather than collecting it.
    parcel = shipments.find_one(
        {"employee_id": employee_doc["employee_id"], "direction": "to_employee",
         "status": {"$ne": "cancelled"}},
        sort=[("created_at", -1)],
    )

    items = [
        {"id": "welcome_email", "label": "Welcome Email Received",
         "done": status.get("welcome_email_sent", False), "done_at": status.get("welcome_email_sent_at")},
        {"id": "orientation", "label": "Orientation Session",
         "done": status.get("orientation_scheduled", False), "done_at": status.get("orientation_scheduled_at"),
         "meeting": _booking_summary(orientation_booking)},
        {"id": "it_equipment", "label": "Collect IT Equipment",
         "done": equipment_ready, "done_at": equipment_ready_at,
         "shipment": ({"status": parcel["status"], "pos_reference": parcel.get("pos_reference") or "",
                       "tracking_url": POS_TRACKING_URL}
                      if parcel else None)},
        {"id": "profile_setup", "label": "Complete Profile Setup",
         "done": has_photo, "done_at": None},
    ]

    # Only there when HR has given this employee documents during onboarding.
    if given:
        items.insert(1, {"id": "documents_signed", "label": "Documents from HR",
                         "done": all(_flow_doc_complete(d) for d in given), "done_at": None})
    items += _flow_checklist_items(employee_doc["employee_id"], "onboarding")  # surveys HR has given

    completed = sum(1 for i in items if i["done"])
    return items, round(completed / len(items) * 100)


@app.get("/api/employee/me/checklist")
@require_employee
def employee_checklist():
    items, progress_percent = _onboarding_checklist(g.current_employee)
    return jsonify({"items": items, "progress_percent": progress_percent}), 200


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


@app.get("/api/employee/me/equipment")
@require_employee
def employee_my_equipment():
    """What IT has assigned to this employee right now - shown on their
    profile, and the list they hand back when they leave."""
    docs = equipment.find({
        "assigned_to_employee_id": g.current_employee["employee_id"], "status": "assigned",
    }).sort("assigned_date", -1)
    out = [{
        "equipment_id": str(d["_id"]), "photo_url": d.get("photo_url"),
        "name": d.get("name"), "type": d.get("type"), "brand": d.get("brand"), "model": d.get("model"),
        "asset_tag": d.get("asset_tag") or "", "serial_number": d.get("serial_number") or "",
        "assigned_date": d.get("assigned_date"), "condition": d.get("condition"),
    } for d in docs]
    return jsonify({"equipment": out}), 200


# ---------- Returning equipment (the employee's side of offboarding) ----------
#
# The employee sees what they have to hand back, by when and where; fills a
# short checklist per item (data backed up, signed out, accessories, the
# condition and a note); and taps "I'm ready to return" so IT knows. Whether
# an item is returned is still read live from the equipment records - only
# IT receiving it (Products / Scan) marks it returned.
# Stored on the employee: offboarding_status.equipment_prep = {equipment_id:
# {backed_up, signed_out, accessories, condition, note}} and
# offboarding_status.ready_to_return_at.

EQUIPMENT_RETURN_LOCATION = os.environ.get("EQUIPMENT_RETURN_LOCATION", "the IT department")
RETURN_PREP_CHECKS = ("backed_up", "signed_out", "accessories")
RETURN_CONDITIONS = ("Good", "Damaged", "Lost")


def _return_items(emp):
    """Everything this employee has to hand back: the items on IT's return
    request (returned ones included) plus anything still assigned to them."""
    eid = emp["employee_id"]
    still = list(equipment.find({"assigned_to_employee_id": eid, "status": "assigned"}))
    still_ids = {str(e["_id"]) for e in still}
    request_doc = messages.find_one({"employee_id": eid, "kind": "equipment_return_request", "request_status": "open"})
    prep = (emp.get("offboarding_status") or {}).get("equipment_prep") or {}
    items, seen = [], set()
    for it in (request_doc or {}).get("return_items") or []:
        seen.add(it["equipment_id"])
        items.append(dict(it))
    for e in still:
        if str(e["_id"]) not in seen:
            items.append({"equipment_id": str(e["_id"]), "name": e.get("name"), "type": e.get("type"),
                          "asset_tag": e.get("asset_tag") or ""})
    for it in items:
        try:
            doc = equipment.find_one({"_id": ObjectId(it["equipment_id"])}) or {}
        except Exception:  # noqa: BLE001
            doc = {}
        it["returned"] = it["equipment_id"] not in still_ids
        it["returned_at"] = doc.get("last_returned_date") if it["returned"] else None
        # returned | damaged | lost - how IT closed it off
        it["outcome"] = ({"lost": "lost", "under_repair": "damaged"}.get(doc.get("status"), "returned")
                         if it["returned"] else None)
        it["photo_url"] = doc.get("photo_url")
        it["serial_number"] = doc.get("serial_number") or ""
        it["asset_tag"] = it.get("asset_tag") or doc.get("asset_tag") or ""
        it["prep"] = prep.get(it["equipment_id"])
    return items


def _prep_complete(prep):
    """Checklist done for one item: all three ticks and a condition - or the
    item reported lost (nothing to tick then)."""
    if not prep or prep.get("condition") not in RETURN_CONDITIONS:
        return False
    return prep["condition"] == "Lost" or all(prep.get(k) for k in RETURN_PREP_CHECKS)


def _return_parcel(emp):
    """The latest return shipment IT set up for this (remote) leaver, or None."""
    return shipments.find_one({"employee_id": emp["employee_id"], "direction": "return",
                               "status": {"$ne": "cancelled"}}, sort=[("created_at", -1)])


def _returns_payload(emp):
    st = emp.get("offboarding_status") or {}
    parcel = _return_parcel(emp)
    return {"started": True, "last_working_day": st.get("last_working_day"), "location": EQUIPMENT_RETURN_LOCATION,
            "ready_at": st.get("ready_to_return_at"), "items": _return_items(emp),
            # Nothing on record: done only once IT confirms there is nothing to collect.
            "nothing_to_collect_at": (_return_request(emp["employee_id"]) or {}).get("nothing_to_collect_at"),
            # Remote leavers post their equipment back with Pos Malaysia instead.
            "by_post": emp.get("work_location_type") in SHIPPING_WORK_LOCATIONS,
            "posted_at": st.get("posted_at"),
            "shipment": ({"status": parcel.get("status"), "pos_reference": parcel.get("pos_reference") or "",
                          "tracking_url": POS_TRACKING_URL} if parcel else None),
            "qr_image_url": (parcel or {}).get("qr_image_url") or st.get("return_qr_url"),
            # IT cancelled the last parcel ({reason, at}) - the employee sends it again.
            "rejected": st.get("return_rejected"),
            # Remote leavers book the Pos parcel themselves: where it goes, the
            # Pos website, and their own details as the sender.
            "company": {"name": COMPANY_NAME, "address": COMPANY_ADDRESS, "phone": COMPANY_PHONE},
            "pos_url": POS_ECONNOTE_URL,
            "sender": {"name": emp.get("full_name") or "", "phone": emp.get("mobile_number") or "",
                       "address": ", ".join(x for x in (emp.get("address_line"), emp.get("postcode"),
                                                        emp.get("state")) if x)}}


# ---------- What IT still has to do, worked out from the records ----------
#
# IT never ticks a request off by hand. Each card's tasks are read live from
# the equipment and shipment records, so a request is done the moment the
# work really is: everything assigned (and, for remote hires, the parcel
# posted), or everything back from a leaver.

def _outgoing_parcel(employee_id):
    return shipments.find_one({"employee_id": employee_id, "direction": "to_employee",
                               "status": {"$ne": "cancelled"}}, sort=[("created_at", -1)])


def _it_onboarding_tasks(emp):
    """([{id, label, detail, done}], all_done) for a new hire's request."""
    items, _extra, ready, _at = _equipment_fulfilment(emp)
    got = sum(1 for i in items if i["assigned"])
    tasks = [{"id": "assign", "label": "Assign the equipment", "done": ready,
              "detail": f"{got} of {len(items)} assigned" if items else "Nothing was requested"}]
    if emp.get("work_location_type") in SHIPPING_WORK_LOCATIONS:
        parcel = _outgoing_parcel(emp["employee_id"]) or {}
        st, ref = parcel.get("status"), parcel.get("pos_reference") or ""
        tasks.append({"id": "parcel", "label": "Create the Pos Malaysia parcel",
                      "done": st in ("order_created", "dropped_off", "delivered"),
                      "detail": f"Reference {ref}" if ref else "Not created yet"})
        tasks.append({"id": "posted", "label": "Post the parcel", "done": st in ("dropped_off", "delivered"),
                      "detail": {"dropped_off": "Dropped off at Pos", "delivered": "Delivered"}.get(st, "Not posted yet")})
    return tasks, all(t["done"] for t in tasks)


def _it_return_tasks(emp, req, items=None):
    """([{id, label, detail, done}], all_done) for a leaver's equipment return."""
    items = _return_items(emp) if items is None else items
    st = emp.get("offboarding_status") or {}
    back = sum(1 for i in items if i["returned"])
    all_back = bool(items) and back == len(items)
    tasks = []
    if not items:
        tasks.append({"id": "confirm", "label": "Confirm there is nothing to collect",
                      "done": bool((req or {}).get("nothing_to_collect_at")),
                      "detail": "No equipment is on record for this person"})
    else:
        ready = st.get("ready_to_return_at")
        tasks.append({"id": "ready", "label": "Employee completes their return checklist",
                      "done": bool(ready) or all_back,
                      "detail": f"Ready since {str(ready)[:10]}" if ready else "Waiting for the employee"})
        if emp.get("work_location_type") in SHIPPING_WORK_LOCATIONS:
            parcel = _return_parcel(emp) or {}
            ref = parcel.get("pos_reference") or ""
            tasks.append({"id": "posted", "label": "Employee posts the parcel with Pos Malaysia",
                          "done": parcel.get("status") in ("dropped_off", "delivered") or all_back,
                          "detail": f"Tracking {ref} - check it on Pos tracking" if ref else "No tracking number yet"})
        tasks.append({"id": "receive", "label": "Receive each item (Products / Scan)", "done": all_back,
                      "detail": f"{back} of {len(items)} received"})
    return tasks, _equipment_return_done(emp["employee_id"])


def _it_progress_text(emp, kind):
    """For HR's flow-step hint: what IT has done so far, read from the records."""
    if kind == "equipment_request":
        tasks, _done = _it_onboarding_tasks(emp)
    else:
        tasks, _done = _it_return_tasks(emp, _return_request(emp["employee_id"]))
    left = [f"{t['label'].lower()} ({t['detail']})" for t in tasks if not t["done"]]
    return ("Still to do: " + "; ".join(left) + ". ") if left else ""


@app.get("/api/employee/me/returns")
@require_employee
def employee_my_returns():
    emp = g.current_employee
    if not (emp.get("offboarding_status") or {}).get("started"):
        return jsonify({"started": False}), 200
    return jsonify(_returns_payload(emp)), 200


@app.put("/api/employee/me/returns/<equipment_id>")
@require_employee
def employee_save_return_prep(equipment_id):
    emp = g.current_employee
    if not (emp.get("offboarding_status") or {}).get("started"):
        return jsonify({"message": "Offboarding hasn't started."}), 400
    try:
        item = equipment.find_one({"_id": ObjectId(equipment_id), "assigned_to_employee_id": emp["employee_id"],
                                   "status": "assigned"})
    except Exception:  # noqa: BLE001
        item = None
    if not item:
        return jsonify({"message": "That item isn't with you any more."}), 404
    body = request.get_json(silent=True) or {}
    condition = body.get("condition")
    if condition not in RETURN_CONDITIONS:
        return jsonify({"message": "Choose the condition: Good, Damaged or Lost."}), 400
    prep = {k: bool(body.get(k)) for k in RETURN_PREP_CHECKS}
    prep.update({"condition": condition, "note": (body.get("note") or "").strip()[:500],
                 "updated_at": datetime.now(timezone.utc).isoformat()})
    users.update_one({"employee_id": emp["employee_id"]},
                     {"$set": {f"offboarding_status.equipment_prep.{equipment_id}": prep}})
    fresh = users.find_one({"employee_id": emp["employee_id"]})
    return jsonify({"message": "Saved.", **_returns_payload(fresh)}), 200


@app.post("/api/employee/me/returns/ready")
@require_employee
def employee_ready_to_return():
    """'I'm ready to return' - tells IT, once every item still with the
    employee has its checklist done."""
    emp = g.current_employee
    if not (emp.get("offboarding_status") or {}).get("started"):
        return jsonify({"message": "Offboarding hasn't started."}), 400
    outstanding = [i for i in _return_items(emp) if not i["returned"]]
    if not outstanding:
        return jsonify({"message": "Nothing left to return - thank you!"}), 400
    unfinished = [i.get("name") or i.get("type") or "item" for i in outstanding if not _prep_complete(i["prep"])]
    if unfinished:
        return jsonify({"message": "Finish the checklist first for: " + ", ".join(unfinished) + "."}), 400
    now = datetime.now(timezone.utc).isoformat()
    users.update_one({"employee_id": emp["employee_id"]}, {"$set": {"offboarding_status.ready_to_return_at": now}})
    names = ", ".join(i.get("name") or i.get("type") or "item" for i in outstanding)
    last_day = _as_date((emp.get("offboarding_status") or {}).get("last_working_day"))
    _notify("it", None, "notification", f"{emp['full_name']} is ready to return equipment",
            f"{len(outstanding)} item{'s' if len(outstanding) != 1 else ''}: {names}."
            + (f" Last working day: {last_day.strftime('%d %b %Y')}." if last_day else ""),
            {"type": "requests"})
    fresh = users.find_one({"employee_id": emp["employee_id"]})
    return jsonify({"message": "IT has been told you're ready.", **_returns_payload(fresh)}), 200


@app.post("/api/employee/me/returns/posted")
@require_employee
def employee_posted_return():
    """Remote leaver: they booked the parcel on Pos Malaysia's site themselves
    (to the company address) and posted it. Saves their tracking number on
    the return shipment - creating it if IT hadn't - marks it dropped off and
    sends it to IT to review."""
    emp = g.current_employee
    if not (emp.get("offboarding_status") or {}).get("started"):
        return jsonify({"message": "Offboarding hasn't started."}), 400
    if emp.get("work_location_type") not in SHIPPING_WORK_LOCATIONS:
        return jsonify({"message": "Only remote employees return equipment by post."}), 400
    tracking = ((request.get_json(silent=True) or {}).get("tracking_number") or "").strip()[:60]
    parcel = _return_parcel(emp)
    if not tracking and not (parcel or {}).get("pos_reference"):
        return jsonify({"message": "Enter the tracking number Pos Malaysia gave you."}), 400
    outstanding = [i for i in _return_items(emp) if not i["returned"]]
    unfinished = [i.get("name") or i.get("type") or "item" for i in outstanding if not _prep_complete(i["prep"])]
    if unfinished:
        return jsonify({"message": "Finish the checklist first for: " + ", ".join(unfinished) + "."}), 400

    now = datetime.now(timezone.utc).isoformat()
    st = emp.get("offboarding_status") or {}
    users.update_one({"employee_id": emp["employee_id"]}, {
        "$set": {"offboarding_status.posted_at": now,
                 "offboarding_status.ready_to_return_at": st.get("ready_to_return_at") or now},
        "$unset": {"offboarding_status.return_rejected": ""}})
    if parcel is None:
        result = shipments.insert_one({
            "employee_id": emp["employee_id"], "employee_name": emp["full_name"], "direction": "return",
            "status": "dropped_off", "dropped_off_at": now, "items": _shipment_items(emp, "return"),
            "pos_reference": tracking, "qr_image_url": st.get("return_qr_url"), "notes": "",
            "created_by": emp.get("work_email") or emp.get("personal_email") or "employee", "created_at": now,
            "submitted_by_employee": True, "employee_posted_at": now,
        })
        parcel = shipments.find_one({"_id": result.inserted_id})
    else:
        updates = {"employee_posted_at": now, "submitted_by_employee": True}
        if tracking:
            updates["pos_reference"] = tracking
        if st.get("return_qr_url"):
            updates["qr_image_url"] = st["return_qr_url"]
        if parcel.get("status") in ("pending", "order_created"):
            updates.update({"status": "dropped_off", "dropped_off_at": now})
        shipments.update_one({"_id": parcel["_id"]}, {"$set": updates})
    ref = tracking or parcel.get("pos_reference") or ""
    _notify("hr", None, "notification", f"Return parcel posted: {emp['full_name']}",
            f"They sent their equipment back by Pos Malaysia - tracking {tracking or parcel.get('pos_reference') or ''}.",
            {"type": "shipments"})
    _notify("it", None, "notification", f"Review return parcel: {emp['full_name']}",
            f"{emp['full_name']} posted their equipment with Pos Malaysia - tracking {ref}. "
            "Check it in Shipments (Returns) and receive each item when it arrives.", {"type": "shipments", "direction": "return"})
    fresh = users.find_one({"employee_id": emp["employee_id"]})
    return jsonify({"message": "Sent to IT - they'll check your parcel and tick each item off when it arrives.",
                    **_returns_payload(fresh)}), 200


@app.post("/api/employee/me/returns/qr")
@require_employee
def employee_upload_return_qr():
    """Remote leaver: the screenshot of the QR code Pos Malaysia gave them for
    the return parcel. Kept on their offboarding record and on the return
    shipment (once there is one), where IT sees it."""
    emp = g.current_employee
    if not (emp.get("offboarding_status") or {}).get("started"):
        return jsonify({"message": "Offboarding hasn't started."}), 400
    if emp.get("work_location_type") not in SHIPPING_WORK_LOCATIONS:
        return jsonify({"message": "Only remote employees return equipment by post."}), 400
    file = request.files.get("qr")
    if file is None or file.filename == "":
        return jsonify({"message": "No image was sent."}), 400
    ext = file.filename.rsplit(".", 1)[-1].lower() if "." in file.filename else ""
    if ext not in ALLOWED_PHOTO_EXTENSIONS:
        return jsonify({"message": "The QR image must be a JPG or PNG file."}), 400
    # A new name each time, so a replaced screenshot never shows the cached old one.
    filename = secure_filename(f"return-qr-{emp['employee_id']}-{int(datetime.now().timestamp())}.{ext}")
    file.save(os.path.join(UPLOAD_FOLDER, filename))
    url = f"/uploads/{filename}"
    users.update_one({"employee_id": emp["employee_id"]}, {"$set": {"offboarding_status.return_qr_url": url}})
    parcel = _return_parcel(emp)
    if parcel:
        shipments.update_one({"_id": parcel["_id"]}, {"$set": {"qr_image_url": url}})
    fresh = users.find_one({"employee_id": emp["employee_id"]})
    return jsonify({"message": "QR code uploaded.", **_returns_payload(fresh)}), 200


def _equipment_return_reminders():
    """Runs with the lifecycle sweep. The employee is reminded 3 days and
    1 day before their last working day (and on the day) while items are
    still with them; on the last day HR and IT are warned too. Each one is
    sent once (dedupe keys)."""
    today = _today_my()
    for emp in users.find({"role": "employee", "offboarding_status.started": True,
                           "offboarding_status.completed": {"$ne": True}}):
        eid = emp["employee_id"]
        last_day = _as_date((emp.get("offboarding_status") or {}).get("last_working_day"))
        if not last_day:
            continue
        left = equipment.count_documents({"assigned_to_employee_id": eid, "status": "assigned"})
        if not left:
            continue
        days = (last_day - today).days
        items = f"{left} item{'s' if left != 1 else ''}"
        when = last_day.strftime("%d %b %Y")
        if days in (3, 1, 0):
            _notify("employee", eid, "reminder",
                    "Last day today - return your equipment" if days == 0 else "Return your equipment",
                    f"{items} still with you. Please return {'it' if left == 1 else 'them'} to "
                    f"{EQUIPMENT_RETURN_LOCATION} by {when}.",
                    {"type": "offboarding"}, dedupe_key=f"return-reminder:{eid}:{last_day}:{days}")
        if days == 0:
            for role in ("hr", "it"):
                _notify(role, None, "reminder", f"Equipment not returned: {emp.get('full_name')}",
                        f"{items} still with them on their last working day ({when}).",
                        {"type": "lifecycle"} if role == "hr" else {"type": "requests"},
                        dedupe_key=f"return-due:{eid}:{last_day}")


@app.post("/api/employee/me/password")
@require_employee
def employee_change_password():
    """An employee changing their own SELMS password. The current password
    is checked first, so a session left open on a shared screen can't be
    used to lock the person out."""
    body = request.get_json(silent=True) or {}
    current = body.get("current_password") or ""
    new = body.get("new_password") or ""
    if not current or not new:
        return jsonify({"message": "Current and new password are required."}), 400
    if not bcrypt.checkpw(current.encode("utf-8"), g.current_employee["password_hash"]):
        return jsonify({"message": "Your current password is incorrect."}), 400
    if len(new) < 8:
        return jsonify({"message": "The new password must be at least 8 characters."}), 400
    if new == current:
        return jsonify({"message": "The new password must be different from the current one."}), 400
    users.update_one({"_id": g.current_employee["_id"]}, {
        "$set": {
            "password_hash": bcrypt.hashpw(new.encode("utf-8"), bcrypt.gensalt()),
            "must_change_password": False,
            "password_changed_at": datetime.now(timezone.utc).isoformat(),
        },
        "$unset": {"initial_password": ""},
    })
    return jsonify({"message": "Password changed."}), 200


@app.get("/api/employee/me/bookings")
@require_employee
def employee_my_bookings():
    """The employee's own sessions (orientation, IT handoff, exit interview,
    anything HR/IT booked for them) for their Schedule tab. Optional
    ?start=YYYY-MM-DD&end=YYYY-MM-DD, inclusive; read-only - only HR and IT
    book or change sessions."""
    me = g.current_employee["employee_id"]
    query = {"$or": [{"employee_id": me}, {"attendees.id": me}]}
    start, end = request.args.get("start"), request.args.get("end")
    if start and end:
        query["date"] = {"$gte": start, "$lte": end}
    out = []
    for d in bookings.find(query).sort([("date", 1), ("start_time", 1)]):
        out.append({
            "id": str(d["_id"]),
            "session_type": d.get("session_type"),
            "title": d.get("title"),
            "date": d.get("date"),
            "start_time": d.get("start_time"),
            "duration_minutes": d.get("duration_minutes"),
            "mode": d.get("mode") or "in_person",
            "location": d.get("location") or "",
            "meeting_url": d.get("meeting_url") or "",
            "with": [a.get("name") for a in (d.get("attendees") or []) if a.get("id") != me],
        })
    return jsonify({"bookings": out}), 200


EMPLOYEE_BADGE_SECTIONS = ("onboarding", "offboarding", "documents", "messages")


@app.post("/api/employee/me/seen")
@require_employee
def employee_mark_section_seen():
    """The employee opened a tab (or the chat) - its red badge counts from
    now on. Separate from the bell's 'read everything' marker."""
    section = (request.get_json(silent=True) or {}).get("section")
    if section not in EMPLOYEE_BADGE_SECTIONS:
        return jsonify({"message": "Unknown section."}), 400
    users.update_one({"_id": g.current_employee["_id"]}, {"$set": {
        f"seen_at.{section}": datetime.now(timezone.utc).isoformat(),
    }})
    return jsonify({"message": "Seen."}), 200


def _employee_chat_snapshot(employee_doc):
    status = employee_doc.get("onboarding_status") or {}
    given = list(flow_documents.find({"employee_id": employee_doc["employee_id"]}))
    return (
        f"Employee: {employee_doc['full_name']} "
        f"({employee_doc.get('job_title')}, {employee_doc.get('department')}).\n"
        f"Onboarding started: {status.get('started', False)}.\n"
        f"Welcome email sent: {status.get('welcome_email_sent', False)}.\n"
        f"Orientation scheduled: {status.get('orientation_scheduled', False)}.\n"
        f"IT equipment ready: {status.get('it_equipment_ready', False)}.\n"
        f"Documents from HR: {sum(1 for d in given if _flow_doc_complete(d))} of {len(given)} complete.\n"
        f"Profile photo uploaded: {bool(employee_doc.get('profile_image_url'))}."
    )


@app.post("/api/employee/me/chat")
@require_employee
def employee_chat():
    body = request.get_json(silent=True) or {}
    message = (body.get("message") or "").strip()
    history = body.get("history") or []
    if not message:
        return jsonify({"message": "message is required."}), 400

    system_prompt = (
        "You are SmartBot, an assistant for employees inside the Smart Employee "
        "Lifecycle Management System. Answer using the employee's own status below "
        "and the company FAQ knowledge provided. Never invent policies or statuses "
        "that aren't given to you. If something isn't covered, say to contact HR or "
        "IT directly. Keep answers short and friendly.\n\n"
        "This employee's own status:\n" + _employee_chat_snapshot(g.current_employee) + "\n\n"
        "Company FAQ knowledge:\n" + EMPLOYEE_FAQ
    )
    anthropic_messages = [{"role": m["role"], "content": m["content"]}
                          for m in history if m.get("role") in ("user", "assistant")]
    anthropic_messages.append({"role": "user", "content": message})

    try:
        reply, docs = _chat_with_documents(system_prompt, anthropic_messages)
    except Exception as exc:
        return jsonify({"message": f"Could not reach the assistant: {exc}"}), 502

    return jsonify({"reply": reply, "documents": docs}), 200


# ---------- Messaging (Talk to HR / Talk to IT) ----------
#
# Plain human-to-human messages - separate from the AI chatbot above.
# One thread per (employee, target_role) pair: every employee has at
# most one conversation with "HR" as a whole and one with "IT" as a
# whole, not with a specific staff member, since either role is treated
# as one shared inbox any HR/IT account can see and reply from.
#
# No websockets/Firebase - the client re-polls GET on a timer instead.
# Read state is the same "single marker timestamp" pattern used for
# notifications: one field per (thread, viewer) pair on the employee's
# own record, rather than a read flag on every individual message.

def _serialize_message(doc):
    return {
        "id": str(doc["_id"]),
        "employee_id": doc["employee_id"],
        "employee_name": doc["employee_name"],
        "target_role": doc["target_role"],
        "sender_role": doc["sender_role"],
        "sender_name": doc["sender_name"],
        "content": doc["content"],
        "created_at": doc["created_at"],
        # Only meaningful for sender_role == "system" (e.g. the onboarding
        # equipment notification) - a human message is never "accepted".
        "accepted": doc.get("accepted", False),
        "accepted_by": doc.get("accepted_by"),
        "accepted_at": doc.get("accepted_at"),
    }


@app.get("/api/employee/me/messages/<target_role>")
@require_employee
def employee_get_messages(target_role):
    if target_role not in ("hr", "it"):
        return jsonify({"message": "target_role must be 'hr' or 'it'."}), 400

    employee_id = g.current_employee["employee_id"]
    docs = list(messages.find({"employee_id": employee_id, "target_role": target_role})
                .sort("created_at", 1))

    users.update_one(
        {"_id": g.current_employee["_id"]},
        {"$set": {f"{target_role}_thread_read_by_employee_at": datetime.now(timezone.utc).isoformat()}},
    )
    return jsonify({"messages": [_serialize_message(d) for d in docs]}), 200


@app.post("/api/employee/me/messages/<target_role>")
@require_employee
def employee_send_message(target_role):
    if target_role not in ("hr", "it"):
        return jsonify({"message": "target_role must be 'hr' or 'it'."}), 400

    content = ((request.get_json(silent=True) or {}).get("content") or "").strip()
    if not content:
        return jsonify({"message": "content is required."}), 400

    doc = {
        "employee_id": g.current_employee["employee_id"],
        "employee_name": g.current_employee["full_name"],
        "target_role": target_role,
        "sender_role": "employee",
        "sender_name": g.current_employee["full_name"],
        "content": content,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    result = messages.insert_one(doc)
    doc["_id"] = result.inserted_id
    return jsonify(_serialize_message(doc)), 201


def _staff_inbox(target_role, read_marker_field):
    """Shared by GET /api/hr/messages and GET /api/it/messages: one row
    per employee who has any message in this target_role's threads,
    newest conversation first, with a real unread count computed against
    that staff role's own read marker."""
    docs = list(messages.find({"target_role": target_role}).sort("created_at", 1))
    by_employee = {}
    for d in docs:
        by_employee.setdefault(d["employee_id"], {"employee_name": d["employee_name"], "messages": []})
        by_employee[d["employee_id"]]["messages"].append(d)

    rows = []
    for employee_id, thread in by_employee.items():
        emp = users.find_one({"employee_id": employee_id, "role": "employee"})
        read_marker = (emp or {}).get(read_marker_field)
        unread = sum(
            1 for m in thread["messages"]
            if m["sender_role"] in ("employee", "system") and (not read_marker or m["created_at"] > read_marker)
        )
        last = thread["messages"][-1]
        rows.append({
            "employee_id": employee_id,
            "employee_name": thread["employee_name"],
            "profile_image_url": (emp or {}).get("profile_image_url"),
            "last_message": last["content"],
            "last_message_at": last["created_at"],
            "last_sender_role": last["sender_role"],
            "unread_count": unread,
        })

    rows.sort(key=lambda r: r["last_message_at"], reverse=True)
    return rows


@app.get("/api/hr/messages")
@require_hr
def hr_list_messages():
    return jsonify({"conversations": _staff_inbox("hr", "hr_thread_read_by_hr_at")}), 200


@app.get("/api/hr/messages/<employee_id>")
@require_hr
def hr_get_thread(employee_id):
    docs = list(messages.find({"employee_id": employee_id, "target_role": "hr"}).sort("created_at", 1))
    users.update_one(
        {"employee_id": employee_id},
        {"$set": {"hr_thread_read_by_hr_at": datetime.now(timezone.utc).isoformat()}},
    )
    return jsonify({"messages": [_serialize_message(d) for d in docs]}), 200


@app.post("/api/hr/messages/<employee_id>")
@require_hr
def hr_send_message(employee_id):
    emp = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not emp:
        return jsonify({"message": "Employee not found."}), 404

    content = ((request.get_json(silent=True) or {}).get("content") or "").strip()
    if not content:
        return jsonify({"message": "content is required."}), 400

    doc = {
        "employee_id": employee_id,
        "employee_name": emp["full_name"],
        "target_role": "hr",
        "sender_role": "hr",
        "sender_name": g.current_user.get("full_name") or "HR",
        "content": content,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    result = messages.insert_one(doc)
    doc["_id"] = result.inserted_id
    return jsonify(_serialize_message(doc)), 201


@app.get("/api/it/messages")
@require_it
def it_list_messages():
    return jsonify({"conversations": _staff_inbox("it", "it_thread_read_by_it_at")}), 200


@app.get("/api/it/messages/<employee_id>")
@require_it
def it_get_thread(employee_id):
    docs = list(messages.find({"employee_id": employee_id, "target_role": "it"}).sort("created_at", 1))
    users.update_one(
        {"employee_id": employee_id},
        {"$set": {"it_thread_read_by_it_at": datetime.now(timezone.utc).isoformat()}},
    )
    return jsonify({"messages": [_serialize_message(d) for d in docs]}), 200


@app.post("/api/it/messages/<employee_id>")
@require_it
def it_send_message(employee_id):
    emp = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not emp:
        return jsonify({"message": "Employee not found."}), 404

    content = ((request.get_json(silent=True) or {}).get("content") or "").strip()
    if not content:
        return jsonify({"message": "content is required."}), 400

    doc = {
        "employee_id": employee_id,
        "employee_name": emp["full_name"],
        "target_role": "it",
        "sender_role": "it",
        "sender_name": g.current_user.get("full_name") or "IT",
        "content": content,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    result = messages.insert_one(doc)
    doc["_id"] = result.inserted_id
    return jsonify(_serialize_message(doc)), 201


@app.post("/api/it/messages/<message_id>/accept")
@require_it
def it_accept_message(message_id):
    """IT explicitly acknowledging a system-authored notification (e.g.
    'prepare equipment for this new hire') - a real action, not just
    reading the thread. Only meaningful on sender_role == 'system'
    messages; accepting a human message would be a no-op anyone could
    confuse with actually replying, so it's rejected instead."""
    try:
        doc = messages.find_one({"_id": ObjectId(message_id)})
    except Exception:
        return jsonify({"message": "Invalid message id."}), 400
    if not doc:
        return jsonify({"message": "Message not found."}), 404
    if doc.get("sender_role") != "system":
        return jsonify({"message": "Only system notifications can be accepted."}), 400
    if doc.get("request_status") in ("cancelled", "superseded"):
        return jsonify({"message": "This request is no longer active."}), 400

    now = datetime.now(timezone.utc).isoformat()
    messages.update_one({"_id": doc["_id"]}, {"$set": {
        "accepted": True,
        "accepted_by": g.current_user.get("full_name") or "IT",
        "accepted_at": now,
    }})
    doc["accepted"], doc["accepted_by"], doc["accepted_at"] = True, g.current_user.get("full_name") or "IT", now
    what = "equipment return" if doc.get("kind") == "equipment_return_request" else "equipment"
    _notify("hr", None, "notification", f"IT accepted the request: {doc.get('employee_name') or 'an employee'}",
            f"{doc['accepted_by']} accepted the {what} request.", {"type": "lifecycle"})
    return jsonify(_serialize_message(doc)), 200


@app.post("/api/it/returns/<message_id>/nothing-to-collect")
@require_it
def it_confirm_nothing_to_collect(message_id):
    """IT confirming a leaver with no equipment on record really has nothing
    to hand back - the only way such a return counts as done."""
    try:
        doc = messages.find_one({"_id": ObjectId(message_id), "kind": "equipment_return_request",
                                 "request_status": "open"})
    except Exception:  # noqa: BLE001
        return jsonify({"message": "Invalid request id."}), 400
    if not doc:
        return jsonify({"message": "Return request not found."}), 404
    if _equipment_outstanding(doc["employee_id"]):
        return jsonify({"message": "This person still has equipment assigned - retrieve it from Products."}), 400
    by = g.current_user.get("full_name") or "IT"
    messages.update_one({"_id": doc["_id"]}, {"$set": {
        "nothing_to_collect_at": datetime.now(timezone.utc).isoformat(), "nothing_to_collect_by": by,
        "accepted": True, "accepted_by": doc.get("accepted_by") or by,
        "accepted_at": doc.get("accepted_at") or datetime.now(timezone.utc).isoformat(),
    }})
    _notify("hr", None, "notification", f"No equipment to collect: {doc.get('employee_name') or 'an employee'}",
            f"{by} confirmed there is no company equipment to collect.", {"type": "lifecycle"})
    _advance_offboarding_safely(doc["employee_id"])
    return jsonify({"message": "Confirmed - nothing to collect."}), 200


@app.delete("/api/it/messages/<message_id>")
@require_it
def it_delete_notice(message_id):
    """IT clearing an automatic notice (e.g. 'onboarding cancelled - items
    released') once they've read it. Only system notices can be deleted
    this way - never a real conversation message."""
    try:
        doc = messages.find_one({"_id": ObjectId(message_id)})
    except Exception:  # noqa: BLE001
        return jsonify({"message": "Invalid message id."}), 400
    if not doc:
        return jsonify({"message": "Message not found."}), 404
    if doc.get("sender_role") != "system":
        return jsonify({"message": "Only automatic notices can be deleted."}), 400
    messages.delete_one({"_id": doc["_id"]})
    return jsonify({"message": "Deleted."}), 200


@app.get("/api/it/requests")
@require_it
def it_equipment_requests():
    """IT's equipment requests, one per onboarding HR started: who the hire
    is, what they were approved for, and - live from the equipment records -
    which of it has really been assigned. There is deliberately no way to
    mark a request done by hand; it counts as fulfilled only when every
    requested item is assigned. Also carries the account email and one-time
    password IT needs to create the employee's Microsoft account (IT only)."""
    docs = list(messages.find({
        "target_role": "it", "kind": "equipment_request",
        "request_status": "open",
    }).sort("created_at", -1).limit(50))

    out = []
    for d in docs:
        emp = users.find_one({"employee_id": d["employee_id"], "role": "employee"})
        if not emp:
            continue
        items, extra, _ready, fulfilled_at = _equipment_fulfilment(emp)
        # Done by itself once IT has really done the work: everything
        # assigned and, for remote hires, the Pos parcel posted.
        tasks, fulfilled = _it_onboarding_tasks(emp)
        status = d.get("request_status", "open")
        parcel = _outgoing_parcel(emp["employee_id"])
        provisioning = d.get("provisioning") or {}
        out.append({
            "message_id": str(d["_id"]),
            "created_at": d["created_at"],
            "status": status,  # open | cancelled
            "tasks": tasks,
            "deadline": (emp.get("hire_date") or "")[:10] or None,
            "fulfilled": fulfilled and status == "open",
            "fulfilled_at": fulfilled_at,
            "items": items,
            "extra_assigned": extra,
            "assigned_count": sum(1 for i in items if i["assigned"]),
            "needed_count": len(items),
            "employee": {
                "employee_id": emp["employee_id"],
                "full_name": emp["full_name"],
                "job_title": emp.get("job_title"),
                "department": emp.get("department"),
                "line_manager": emp.get("line_manager"),
                "hire_date": (emp.get("hire_date") or "")[:10],
                "work_location_type": emp.get("work_location_type"),
                "personal_email": emp.get("personal_email"),
                "mobile_number": emp.get("mobile_number"),
                "address_line": emp.get("address_line"),
                "postcode": emp.get("postcode"),
                "state": emp.get("state"),
                "profile_image_url": emp.get("profile_image_url"),
            },
            "account": {
                "email": emp.get("work_email"),
                "initial_password": provisioning.get("initial_password"),  # None once closed
            },
            "needs_shipping": emp.get("work_location_type") in SHIPPING_WORK_LOCATIONS,
            "shipment": ({"status": parcel["status"], "pos_reference": parcel.get("pos_reference") or ""}
                         if parcel else None),
        })

    # Work to do first (open and unfulfilled), then finished, then cancelled.
    def rank(r):
        if r["status"] != "open":
            return 2
        return 1 if r["fulfilled"] else 0
    out.sort(key=rank)

    # Equipment to collect back from people being offboarded. Like the
    # onboarding requests above, "returned" is read live from the equipment
    # records - IT can't tick it off without really retrieving the items.
    returns = []
    for d in messages.find({
        "target_role": "it", "kind": "equipment_return_request", "request_status": "open",
    }).sort("created_at", -1).limit(50):
        emp = users.find_one({"employee_id": d["employee_id"], "role": "employee"})
        if not emp:
            continue
        # Same items the employee sees: photo, tag, returned / outcome, their checklist.
        items = _return_items(emp)
        status_doc = emp.get("offboarding_status") or {}
        tasks, fulfilled = _it_return_tasks(emp, d, items)
        parcel = _return_parcel(emp)
        returns.append({
            "message_id": str(d["_id"]),
            "created_at": d["created_at"],
            "ready_at": status_doc.get("ready_to_return_at"),
            "posted_at": status_doc.get("posted_at"),
            "items": items,
            "tasks": tasks,
            "returned_count": sum(1 for i in items if i["returned"]),
            "total_count": len(items),
            "fulfilled": fulfilled,
            "nothing_to_collect_at": d.get("nothing_to_collect_at"),
            "nothing_to_collect_by": d.get("nothing_to_collect_by"),
            "last_working_day": d.get("last_working_day") or status_doc.get("last_working_day"),
            "departure_type": d.get("departure_type") or status_doc.get("departure_type"),
            "location": EQUIPMENT_RETURN_LOCATION,
            "by_post": emp.get("work_location_type") in SHIPPING_WORK_LOCATIONS,
            "shipment": ({"status": parcel.get("status"), "pos_reference": parcel.get("pos_reference") or "",
                          "from_employee": bool(parcel.get("submitted_by_employee"))} if parcel else None),
            "employee": {
                "employee_id": emp["employee_id"],
                "full_name": emp["full_name"],
                "job_title": emp.get("job_title"),
                "department": emp.get("department"),
                "work_location_type": emp.get("work_location_type"),
                "profile_image_url": emp.get("profile_image_url"),
                "personal_email": emp.get("personal_email"),
                "mobile_number": emp.get("mobile_number"),
            },
        })
    returns.sort(key=lambda r: r["fulfilled"])  # work to do first

    notices = [
        {"id": str(n["_id"]), "content": n["content"], "created_at": n["created_at"],
         "employee_name": n.get("employee_name")}
        for n in messages.find({
            "target_role": "it", "kind": {"$in": ["onboarding_cancelled", "offboarding_cancelled"]},
        }).sort("created_at", -1)
    ]
    return jsonify({"requests": out, "returns": returns, "notices": notices}), 200


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

    employee_id = emp["employee_id"]
    for reply in messages.find({
        "employee_id": employee_id, "sender_role": {"$in": ["hr", "it"]},
    }):
        label = "HR" if reply["sender_role"] == "hr" else "IT"
        events.append((f"message_{reply['_id']}", f"New message from {label}",
                        reply["content"][:80], reply["created_at"]))

    def section_of(eid):
        """Which part of the app an event belongs to (for the red badges on
        the tabs and the chat bubble). The employee's own actions - signing
        a document - belong nowhere: nobody needs a badge for what they did."""
        if eid in ("welcome_email", "orientation_scheduled", "it_equipment_ready"):
            return "onboarding"
        if eid in ("offboarding_started", "exit_interview_scheduled", "access_revoked"):
            return "offboarding"
        if eid.startswith("message_"):
            return "messages"
        return None

    out = [
        {"id": eid, "title": title, "message": msg, "at": at, "kind": "notification",
         "section": section_of(eid), "read": bool(read_before) and read_before >= at}
        for eid, title, msg, at in events
    ]
    # Stored notifications and AI reminders for this employee.
    for n in notifications.find({"recipient_role": "employee", "recipient_id": employee_id}):
        link_type = (n.get("link") or {}).get("type")
        out.append({"id": f"n_{n['_id']}", "title": n["title"], "message": n["body"],
                    "at": n["created_at"], "kind": n["kind"],
                    "section": link_type if link_type in ("onboarding", "offboarding") else None,
                    "read": bool(read_before) and read_before >= n["created_at"]})
    out.sort(key=lambda n: n["at"], reverse=True)

    # Red badge counts: what's new in each section since the employee last
    # opened it. Documents also counts what still needs signing, plus files
    # HR shared since the Documents tab was last opened.
    seen = emp.get("seen_at") or {}

    def is_new(section, at):
        return not seen.get(section) or at > seen[section]

    badges = {s: sum(1 for n in out if n["section"] == s and is_new(s, n["at"]))
              for s in ("onboarding", "offboarding", "messages")}
    # The Documents tab only holds what HR gave this employee during onboarding.
    badges["documents"] = _flow_items_badge(employee_id, seen.get("documents"))

    return jsonify({"notifications": out, "unread_count": sum(1 for n in out if not n["read"]),
                    "badges": badges}), 200


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

    items, progress_percent = _offboarding_checklist(g.current_employee)
    return jsonify({
        "started": True,
        "departure_type": status.get("departure_type"),
        "last_working_day": status.get("last_working_day"),
        "items": items,
        "progress_percent": progress_percent,
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
        "exit_interview_mode": "in_person",
        "offboarding_email_sent": False, "offboarding_email_sent_at": None,
        "it_notified": False, "it_notified_at": None,
        "access_revoked": False, "access_revoked_at": None,
    }


@app.post("/api/employees/<employee_id>/offboarding/initiate")
@require_hr
def initiate_offboarding(employee_id):
    """Starts offboarding and runs the flow from its first step, exactly like
    onboarding's auto-start: if the first step is the offboarding email an AI
    draft comes back for HR to review and send; the steps after it only run as
    each one is completed (see _advance_offboarding)."""
    doc = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not doc:
        return jsonify({"message": "Employee not found."}), 404

    body = request.get_json(silent=True) or {}
    departure_type = (body.get("departure_type") or "").strip()
    last_working_day = (body.get("last_working_day") or "").strip()
    if not departure_type or not last_working_day:
        return jsonify({"message": "Departure type and last working day are required."}), 400
    mode = body.get("exit_interview_mode") or "in_person"
    if mode not in MEETING_MODES:
        mode = "in_person"

    now = datetime.now(timezone.utc).isoformat()
    already = (doc.get("offboarding_status") or {}).get("started")
    updates = {
        "offboarding_status.started": True,
        "offboarding_status.started_by": g.current_user["email"],
        "offboarding_status.departure_type": departure_type,
        "offboarding_status.last_working_day": last_working_day,
        "offboarding_status.notes": (body.get("notes") or "").strip(),
        "offboarding_status.exit_interview_mode": mode,
    }
    if not already:
        updates["offboarding_status.started_at"] = now
    users.update_one({"employee_id": employee_id}, {"$set": updates})

    # Only draft the email if that step is still to be done.
    draft = {"subject": "", "body": ""}
    fresh = users.find_one({"employee_id": employee_id})
    email_node = next((n for n in _offboarding_step_nodes(employee_id)
                       if n.get("label") == "Send offboarding email"), None)
    if email_node is not None and not _offboarding_step_done(fresh, email_node) \
            and not (fresh.get("offboarding_status") or {}).get("email_saved"):
        draft = draft_offboarding_email(fresh)

    summary = _advance_offboarding(employee_id)
    fresh = users.find_one({"employee_id": employee_id})
    run = _offboarding_run(fresh)
    current = next((s for s in run if s["state"] == "current"), None)
    return jsonify({
        "message": "Offboarding initiated.",
        "subject": draft["subject"],
        "body": draft["body"],
        "it_notified": summary["it_notified"],
        "email_sent": bool((fresh.get("offboarding_status") or {}).get("offboarding_email_sent")),
        "exit_interview": summary["exit_interview"],
        "meeting_warning": summary["warning"],
        "current_step": current["label"] if current else None,
        "steps": run,
    }), 200


@app.get("/api/offboarding/active")
@require_hr
def offboarding_active_list():
    """Everyone HR has started offboarding for, with real progress - feeds
    the history panel on the Offboarding tab (same idea as onboarding's)."""
    out = []
    for d in users.find({"role": "employee", "offboarding_status.started": True}):
        _items, progress_percent = _offboarding_checklist(d)
        status = d.get("offboarding_status") or {}
        out.append({
            "employee_id": d["employee_id"],
            "full_name": d["full_name"],
            "department": d.get("department"),
            "job_title": d.get("job_title"),
            "profile_image_url": d.get("profile_image_url"),
            "started_at": status.get("started_at"),
            "last_working_day": status.get("last_working_day"),
            "departure_type": status.get("departure_type"),
            "progress_percent": progress_percent,
            "completed": bool(status.get("completed")),
            "completed_at": status.get("completed_at"),
            "login_status": _login_status_text(d),
        })
    out.sort(key=lambda e: e["started_at"] or "", reverse=True)
    return jsonify({"employees": out}), 200


@app.post("/api/offboarding/<employee_id>/cancel")
@require_hr
def offboarding_cancel(employee_id):
    """Undoes a started offboarding: clears its status, removes the exit
    interview booking (and its Google event, if any) and IT's open equipment
    return request. If IT had already been told, they get a short notice so
    they don't go collecting equipment for someone who isn't leaving. An
    offboarding email that was already sent can't be recalled - that comes
    back as a warning."""
    doc = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not doc:
        return jsonify({"message": "Employee not found."}), 404
    status = doc.get("offboarding_status") or {}
    if not status.get("started"):
        return jsonify({"message": "Offboarding hasn't been started for this employee."}), 400

    warnings = []
    if status.get("offboarding_email_sent"):
        warnings.append("The offboarding email was already sent to the employee - it cannot be recalled.")

    _clear_flow_items(employee_id, "offboarding")
    users.update_one({"employee_id": employee_id}, {"$unset": {"offboarding_status": ""}})
    removed = _delete_booking_docs({"employee_id": employee_id, "session_type": "exit_interview"})
    messages.delete_many({
        "employee_id": employee_id, "kind": "equipment_return_request", "request_status": "open",
    })
    notified_it = bool(status.get("it_notified"))
    if notified_it:
        messages.insert_one({
            "employee_id": employee_id,
            "employee_name": doc["full_name"],
            "target_role": "it",
            "sender_role": "system",
            "sender_name": "SELMS System",
            "content": f"Offboarding for {doc['full_name']} was cancelled by HR - "
                       f"there is no need to collect their equipment.",
            "kind": "offboarding_cancelled",
            "created_at": datetime.now(timezone.utc).isoformat(),
        })
    return jsonify({"message": "Offboarding cancelled.", "removed_bookings": removed,
                    "warnings": warnings, "it_notified_of_cancellation": notified_it}), 200


@app.put("/api/employees/<employee_id>/offboarding/details")
@require_hr
def save_offboarding_details(employee_id):
    """Departure type, last working day and notes, saved BEFORE offboarding
    starts - the exit interview is then planned on or before that day.
    Nothing starts here (and the login is never closed for a draft: that
    only happens once offboarding is started)."""
    doc = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not doc:
        return jsonify({"message": "Employee not found."}), 404
    if (doc.get("offboarding_status") or {}).get("started"):
        return jsonify({"message": "Offboarding has already started."}), 400
    body = request.get_json(silent=True) or {}
    departure_type = (body.get("departure_type") or "").strip()
    last_working_day = (body.get("last_working_day") or "").strip()
    if not departure_type or _as_date(last_working_day) is None:
        return jsonify({"message": "Departure type and last working day (YYYY-MM-DD) are required."}), 400
    users.update_one({"employee_id": employee_id}, {"$set": {
        "offboarding_status.departure_type": departure_type,
        "offboarding_status.last_working_day": last_working_day,
        "offboarding_status.notes": (body.get("notes") or "").strip(),
    }})
    return jsonify({"message": "Departure details saved."}), 200


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
        # Departure details HR saved before Start (so the exit interview can
        # be planned before the last working day) - nothing has started yet.
        return jsonify({"started": False, "departure_type": status.get("departure_type"),
                        "last_working_day": status.get("last_working_day"), "notes": status.get("notes")}), 200

    items, progress_percent = _offboarding_checklist(doc)
    return jsonify({
        "started": True,
        "departure_type": status.get("departure_type"),
        "last_working_day": status.get("last_working_day"),
        "notes": status.get("notes"),
        "items": items,
        "progress_percent": progress_percent,
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
    _advance_offboarding_safely(employee_id)
    return jsonify({"message": "Updated."}), 200


# ---------- Flow-driven offboarding ----------
#
# Offboarding follows the employee's flow chart one step at a time, in the
# order shown - the same idea as onboarding. A step is "done" when its real
# condition is met, the run stops at the first step that isn't, and the next
# step only starts once it is. SELMS performs "Schedule exit interview" and
# the "tell IT" part of "Retrieve IT equipment" itself the moment they're reached; the rest wait for a person
# (HR sends the email, IT retrieves the equipment, HR ticks off a custom
# step). _advance_offboarding is idempotent and is called whenever something
# that could unblock the next step happens.

OFFBOARDING_AUTO_STEPS = ("Schedule exit interview", END_OFFBOARDING)


def _offboarding_step_nodes(employee_id):
    """The flow's steps in order, minus the trigger."""
    return [n for n in _offboarding_flow_nodes(employee_id) if n.get("id") != "trigger"]


def _offboarding_step_kind(node):
    label = node.get("label")
    if node.get("step") in ("notification", "email"):
        return "auto"      # SELMS sends it when it is due
    if node.get("step") in EMPLOYEE_STEP_TYPES:
        return "employee"  # the employee does it (documents / survey)
    if label in OFFBOARDING_AUTO_STEPS:
        return "auto"      # SELMS does it when reached
    if label == "Retrieve IT equipment":
        return "it"        # IT does it, SELMS watches for the result
    return "hr"            # HR does it (send the email, tick off a custom step)


def _exit_interview_booking(employee_id):
    return bookings.find_one(
        {"employee_id": employee_id, "session_type": "exit_interview"},
        sort=[("date", 1), ("start_time", 1)],
    )


def _equipment_outstanding(employee_id):
    return equipment.count_documents({"assigned_to_employee_id": employee_id, "status": "assigned"})


def _return_request(employee_id):
    return messages.find_one({"employee_id": employee_id, "kind": "equipment_return_request",
                              "request_status": "open"}, sort=[("created_at", -1)])


def _equipment_return_done(employee_id):
    """Equipment counts as returned only through IT: every item that was with
    the employee has been received (or recorded lost) in Products / Scan. An
    empty list never counts on its own - when nothing is on record, IT must
    confirm there is nothing to collect on the return request."""
    if _equipment_outstanding(employee_id):
        return False
    req = _return_request(employee_id)
    if not req:
        return False  # IT hasn't even been told yet
    return bool(req.get("return_items")) or bool(req.get("nothing_to_collect_at"))


def _offboarding_step_done(emp, node):
    if node.get("step") == "email":
        return bool((((emp.get("offboarding_status") or {}).get("email_steps") or {}).get(node.get("id")) or {}).get("done_at"))
    if node.get("step") == "notification":
        return node.get("id") in ((emp.get("offboarding_status") or {}).get("notification_steps") or {})
    if node.get("step") in EMPLOYEE_STEP_TYPES:
        return _custom_step_done(emp, node, "offboarding")
    status = emp.get("offboarding_status") or {}
    label = node.get("label")
    if label == "Send offboarding email":
        return bool(status.get("offboarding_email_sent"))
    if label == "Retrieve IT equipment":
        return _equipment_return_done(emp["employee_id"])
    if label == "Schedule exit interview":
        return bool(status.get("exit_interview_scheduled")) or bool(_exit_interview_booking(emp["employee_id"]))
    if label == END_OFFBOARDING:
        return bool(status.get("completed"))
    return node.get("id") in (status.get("manual_steps") or {})


def _offboarding_step_hint(emp, node):
    if node.get("step") == "email":
        cfg = node.get("email") or {}
        err = ((((emp.get("offboarding_status") or {}).get("email_steps") or {}).get(node.get("id")) or {}).get("error"))
        return (f"SELMS emails {_email_step_recipients_text(cfg)}: \"{cfg.get('subject') or ''}\"."
                + (f" Last try failed: {err}" if err else ""))
    if node.get("step") == "notification":
        return f"SELMS sends this notification to {_notification_recipients_text(node.get('notify') or {})}."
    if node.get("step") in EMPLOYEE_STEP_TYPES:
        return _custom_step_hint(emp, node, "offboarding")
    label = node.get("label")
    if label == "Send offboarding email":
        if (emp.get("offboarding_status") or {}).get("email_saved"):
            return "Saved. SELMS sends it when this step comes due."
        return "HR reviews and saves the offboarding email. SELMS sends it when this step comes due."
    if label == "Retrieve IT equipment":
        left = _equipment_outstanding(emp["employee_id"])
        told = (emp.get("offboarding_status") or {}).get("it_notified")
        req = _return_request(emp["employee_id"])
        if told and req and not left and not req.get("return_items"):
            return ("IT has been told. No equipment is on record for this person - "
                    "waiting for IT to confirm there is nothing to collect.")
        if not told:
            return f"SELMS will tell IT. Waiting for IT to retrieve the equipment ({left} item(s) still with the employee)."
        return "IT has been told. " + (_it_progress_text(emp, "equipment_return_request") or "Everything is back.")
    if label == "Schedule exit interview":
        return "SELMS books the next free slot before the last working day."
    if label == END_OFFBOARDING:
        return "Done by itself once every step above is finished. The employee's login then closes after the last working day."
    return "Tick this off when it's been done."


def _offboarding_run(emp):
    """Per-step state for the flow chart: "done", or "current" for every
    step still open (steps don't wait on each other)."""
    steps = []
    for node in _offboarding_step_nodes(emp["employee_id"]):
        state = "done" if _offboarding_step_done(emp, node) else "current"
        steps.append({
            "id": node["id"], "label": node.get("label"),
            "kind": _offboarding_step_kind(node),
            "state": state,
            "hint": _timed_hint(emp, node, "offboarding", _offboarding_step_hint(emp, node)) if state == "current" else None,
            **_timing_fields(emp, node, "offboarding", state),
        })
    return steps


def _fallback_offboarding_email(emp, status):
    last_day = status.get("last_working_day") or "your last working day"
    return {
        "subject": f"Your offboarding details, {emp['full_name']}",
        "body": (
            f"Hi {emp['full_name']},\n\n"
            f"This email confirms that your last working day with us is {last_day}. "
            f"Before then, please return all company equipment to the IT team, and HR will "
            f"be in touch to arrange your exit interview.\n\n"
            f"If you have any questions in the meantime, just reply to HR.\n\n"
            f"Warm regards,\nHR Team"
        ),
    }


def draft_offboarding_email(emp, instruction=""):
    """{"subject", "body"} for HR to review - AI-drafted when a key is set,
    a fixed template otherwise (and on any failure), so it never blocks HR."""
    status = emp.get("offboarding_status") or {}
    if not ANTHROPIC_API_KEY:
        return _fallback_offboarding_email(emp, status)
    prompt = (
        f"Write a short, professional email to an employee who is leaving the company. "
        f"Name: {emp['full_name']}. Job title: {emp.get('job_title')}. Department: {emp.get('department')}. "
        f"Departure type: {status.get('departure_type')}. Last working day: {status.get('last_working_day')}. "
        f"Say that they should return all company equipment to the IT team before their last day and "
        f"that HR will arrange an exit interview. Do not mention reasons for leaving, do not invent "
        f"policies or dates, no placeholders like [Company Name]. Under 120 words, warm but neutral. "
        + (f"Additional instruction: {instruction}. " if instruction else "")
        + 'Respond ONLY as JSON: {"subject": "...", "body": "..."} - no other text.'
    )
    try:
        text = _chat_completion("You write concise HR emails.", [{"role": "user", "content": prompt}])
        text = text.removeprefix("```json").removeprefix("```").removesuffix("```").strip()
        parsed = _json.loads(text)
        return {"subject": parsed["subject"], "body": parsed["body"]}
    except Exception as exc:  # noqa: BLE001 - any failure just falls back
        print(f"[AI draft] offboarding email falling back to template: {exc}")
        return _fallback_offboarding_email(emp, status)


def _email_booking(booking):
    """Used for sessions HR / IT book by hand on the Smart Schedule (the
    flow's own orientation is described in the welcome email instead).
    Emails everyone in the newly booked session: the employee (personal
    email first - a new hire may not use their work mailbox yet) and the
    other people added. Sent in the background so a slow mail server never
    holds up the booking; a failure is only logged."""
    recipients = _meeting_attendee_emails(booking.get("employee_id"), booking.get("session_type"),
                                          booking.get("attendees"))
    if not recipients:
        return
    title = booking.get("title") or SESSION_TYPES.get(booking.get("session_type"), "Session")
    when = _clock_text(booking.get("date"), booking.get("start_time"))
    mode = booking.get("mode") or "in_person"
    url = booking.get("meeting_url") or ""
    lines = [
        "Hello,",
        "",
        f"A session has been booked for you: {title}.",
        "",
        f"When: {when} ({int(booking.get('duration_minutes') or DEFAULT_SESSION_MINUTES)} minutes)",
        f"Format: {'Online' if mode == 'online' else 'In person'}",
    ]
    if booking.get("location"):
        lines.append(f"Location: {booking['location']}")
    if url:
        lines.append(f"Join link: {url}")
    names = [a.get("name") for a in (booking.get("attendees") or []) if a.get("name")]
    if names:
        lines.append(f"With: {', '.join(names)}")
    lines += ["", "You can also see it in SELMS. If the time doesn't work, please reply to HR.", "", "SELMS"]
    html = _plain_email_html("\n".join(lines))
    subject = f"{title} - {when}"

    def send_all():
        for address in recipients:
            try:
                send_email(to_email=address, subject=subject, html_body=html)
            except Exception as exc:  # noqa: BLE001
                print(f"[booking email] could not email {address}: {exc}")

    threading.Thread(target=send_all, daemon=True).start()


def _plain_email_html(body_text, extra_html=""):
    import html as _htmlmod
    paragraphs = "".join(f"<p>{_htmlmod.escape(line)}</p>" for line in body_text.split("\n") if line.strip())
    return f'<div style="font-family:sans-serif;color:#14161b">{paragraphs}{extra_html}</div>'


def _offboarding_email_html(emp, body_text):
    """The offboarding email with the 'Your exit interview' box (time, format
    and, for online, the Google Meet 'Join online' link) - like the
    orientation box in the welcome email."""
    return _plain_email_html(body_text, _orientation_email_block(
        _exit_interview_booking(emp["employee_id"]), "Your exit interview"))


def _notify_it_equipment_return(emp):
    """Creates IT's equipment-return request (replacing any earlier open one
    for this person), snapshotting what is with the employee right now, and
    records that IT has been notified."""
    now = datetime.now(timezone.utc).isoformat()
    employee_id = emp["employee_id"]
    messages.delete_many({"employee_id": employee_id, "kind": "equipment_return_request", "request_status": "open"})
    assigned = list(equipment.find({"assigned_to_employee_id": employee_id, "status": "assigned"}))
    items = [{"equipment_id": str(a["_id"]), "name": a.get("name"), "type": a.get("type"),
              "asset_tag": a.get("asset_tag") or ""} for a in assigned]
    status = emp.get("offboarding_status") or {}
    line = ", ".join(i["name"] or i["type"] or "item" for i in items) or "no equipment currently assigned"
    last_day = status.get("last_working_day") or "not set"
    messages.insert_one({
        "employee_id": employee_id,
        "employee_name": emp["full_name"],
        "target_role": "it",
        "sender_role": "system",
        "sender_name": "SELMS System",
        "content": f"Equipment return for {emp['full_name']}: {line}. Last working day: {last_day}.",
        "kind": "equipment_return_request",
        "request_status": "open",
        "return_items": items,
        "last_working_day": status.get("last_working_day"),
        "departure_type": status.get("departure_type"),
        "created_at": now,
    })
    users.update_one({"employee_id": employee_id}, {"$set": {
        "offboarding_status.it_notified": True, "offboarding_status.it_notified_at": now,
    }})
    _notify("it", None, "notification", f"Equipment return: {emp['full_name']}",
            f"{line}. Last working day: {last_day}.", {"type": "requests"})


def _book_exit_interview(emp, not_before=None, plan=None):
    """Books the next free slot on or before the last working day, in the
    format chosen when offboarding started (creating the Meet link for
    online). Returns (slot_or_None, warning)."""
    status = emp.get("offboarding_status") or {}
    fields = _plan_fields(emp, plan, "exit_interview", _default_meeting_mode(emp))
    mode = fields["mode"]
    if mode not in MEETING_MODES:
        mode = "in_person"
    last_day = status.get("last_working_day")
    slot = _find_next_available_slot(DEFAULT_SESSION_MINUTES, not_after=last_day, not_before=not_before)
    if slot is None and not_before:
        slot = _find_next_available_slot(DEFAULT_SESSION_MINUTES, not_after=last_day)
    if slot is None:
        return None, "No free exit interview slot before the last working day - book one from Smart Schedule."

    now = datetime.now(timezone.utc).isoformat()
    booking = {
        "employee_id": emp["employee_id"],
        "employee_name": emp["full_name"],
        "session_type": "exit_interview",
        "date": slot["date"],
        "start_time": slot["start_time"],
        "duration_minutes": slot["duration_minutes"],
        **fields,
        "created_at": now,
        "aimed_note": _aimed_note(not_before, slot),
    }
    extra, warning = _provision_meeting(booking)
    booking.update(extra)
    bookings.insert_one(booking)
    users.update_one({"employee_id": emp["employee_id"]}, {"$set": {
        "offboarding_status.exit_interview_scheduled": True,
        "offboarding_status.exit_interview_scheduled_at": now,
    }})
    fmt = "online" if mode == "online" else "in person"
    _notify("employee", emp["employee_id"], "notification", "Exit interview scheduled",
            f"Your exit interview is on {_clock_text(slot['date'], slot['start_time'])} ({fmt}).",
            {"type": "offboarding"})
    _tell_hr_if_moved(emp, "Exit interview", booking["aimed_note"], slot)
    return {**slot, "mode": mode, "meeting_url": booking["meeting_url"]}, warning


def _advance_offboarding(employee_id):
    """Runs the whole flow in order: performs SELMS's own steps as they come
    up and passes over the ones that need a person - those don't hold the
    rest of the flow back. Safe to call any time - does nothing if
    offboarding hasn't been started, and steps already done are skipped."""
    summary = {"it_notified": False, "exit_interview": None, "warning": None}
    email_due = False
    for node in _offboarding_step_nodes(employee_id):
        emp = users.find_one({"employee_id": employee_id, "role": "employee"})
        if not emp or not (emp.get("offboarding_status") or {}).get("started"):
            return summary
        label = node.get("label")
        # "Retrieve IT equipment" starts by telling IT - once, even if the employee
        # has nothing assigned (IT still needs to know they are leaving).
        if (label == "Retrieve IT equipment" and not (emp.get("offboarding_status") or {}).get("it_notified")
                and _step_is_due(emp, node, "offboarding")):
            _notify_it_equipment_return(emp)
            summary["it_notified"] = True
            emp = users.find_one({"employee_id": employee_id, "role": "employee"}) or emp
        if _offboarding_step_done(emp, node):
            continue
        if label == "Send offboarding email":
            st = emp.get("offboarding_status") or {}
            if st.get("email_saved") and st.get("email_subject") and st.get("email_body") \
                    and _step_is_due(emp, node, "offboarding"):
                email_due = True  # sent after this run - see below
            continue
        if node.get("step") == "email":
            if _step_is_due(emp, node, "offboarding"):
                _send_email_step(emp, node, "offboarding")
            continue
        if node.get("step") == "notification":
            if _step_is_due(emp, node, "offboarding"):
                _send_notification_step(emp, node, "offboarding")
            continue
        if node.get("step") in EMPLOYEE_STEP_TYPES:
            if _step_is_due(emp, node, "offboarding"):
                _issue_flow_step(emp, node, "offboarding")
            continue
        if label == "Schedule exit interview":
            slot, warning = _book_exit_interview(emp, not_before=_step_target_at(emp, node, "offboarding"), plan=node.get("meeting"))
            summary["warning"] = warning
            if slot is not None:
                summary["exit_interview"] = slot
        # any other step is done by a person - the flow carries on past it
    if email_due:
        # Last, so the email's "Your exit interview" box (time, format and the
        # Google Meet "Join online" link) shows the session just booked above.
        emp = users.find_one({"employee_id": employee_id, "role": "employee"})
        st = (emp or {}).get("offboarding_status") or {}
        if emp and not st.get("offboarding_email_sent"):
            _send_offboarding_email(emp, st["email_subject"], st["email_body"], advance=False)
    summary["completed"] = _check_completion(employee_id, "offboarding")
    return summary


def _advance_offboarding_safely(employee_id):
    """For hooks inside other routes - advancing the flow must never make
    the action that triggered it fail."""
    if not employee_id:
        return
    try:
        _advance_offboarding(employee_id)
    except Exception as exc:  # noqa: BLE001
        print(f"[offboarding flow] could not advance {employee_id}: {exc}")


@app.get("/api/offboarding/<employee_id>/run")
@require_hr
def offboarding_run(employee_id):
    """Where this employee is in their offboarding flow: every step with its state."""
    emp = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not emp:
        return jsonify({"message": "Employee not found."}), 404
    started = bool((emp.get("offboarding_status") or {}).get("started"))
    return jsonify({"started": started, "steps": _offboarding_run(emp) if started else []}), 200


@app.post("/api/offboarding/<employee_id>/complete-step")
@require_hr
def offboarding_complete_step(employee_id):
    """HR ticking off a step that only a person can complete (a custom step
    they added to the flow). Only a step that's still open can be completed."""
    emp = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not emp:
        return jsonify({"message": "Employee not found."}), 404
    if not (emp.get("offboarding_status") or {}).get("started"):
        return jsonify({"message": "Offboarding hasn't been started."}), 400

    step_id = (request.get_json(silent=True) or {}).get("step_id")
    run = _offboarding_run(emp)
    current = next((s for s in run if s["state"] == "current" and s["id"] == step_id), None)
    if not current:
        return jsonify({"message": "That step isn't open."}), 400
    if current["kind"] != "hr" or current["label"] == "Send offboarding email":
        return jsonify({"message": "This step completes by itself when its work is done."}), 400

    users.update_one({"employee_id": employee_id}, {"$set": {
        f"offboarding_status.manual_steps.{step_id}": datetime.now(timezone.utc).isoformat(),
    }})
    _advance_offboarding_safely(employee_id)
    return jsonify({"message": "Step completed."}), 200


@app.post("/api/offboarding/<employee_id>/draft-email")
@require_hr
def offboarding_draft_email(employee_id):
    emp = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not emp:
        return jsonify({"message": "Employee not found."}), 404
    if not (emp.get("offboarding_status") or {}).get("started"):
        return jsonify({"message": "Start offboarding first."}), 400
    instruction = (request.get_json(silent=True) or {}).get("instruction", "")
    st = emp.get("offboarding_status") or {}
    if not instruction and st.get("email_saved") and st.get("email_subject") and st.get("email_body"):
        return jsonify({"subject": st["email_subject"], "body": st["email_body"], "saved": True,
                        "sent": bool(st.get("offboarding_email_sent")), "started": True}), 200
    return jsonify({**draft_offboarding_email(emp, instruction), "started": True}), 200


@app.post("/api/offboarding/<employee_id>/send-email")
@require_hr
def offboarding_send_email(employee_id):
    emp = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not emp:
        return jsonify({"message": "Employee not found."}), 404
    if not (emp.get("offboarding_status") or {}).get("started"):
        return jsonify({"message": "Start offboarding first."}), 400

    body = request.get_json(silent=True) or {}
    subject = (body.get("subject") or "").strip()
    body_text = (body.get("body") or "").strip()
    if not subject or not body_text:
        return jsonify({"message": "Subject and body are required."}), 400

    to_email = emp.get("personal_email") or emp.get("work_email")
    try:
        send_email(to_email=to_email, subject=subject, html_body=_offboarding_email_html(emp, body_text))
    except Exception as exc:
        return jsonify({"message": f"Could not send email: {exc}"}), 502

    now = datetime.now(timezone.utc).isoformat()
    users.update_one({"employee_id": employee_id}, {"$set": {
        "offboarding_status.offboarding_email_sent": True,
        "offboarding_status.offboarding_email_sent_at": now,
        "offboarding_status.email_subject": subject,
        "offboarding_status.email_body": body_text,
    }})
    summary = _advance_offboarding(employee_id)
    run = _offboarding_run(users.find_one({"employee_id": employee_id}))
    current = next((s for s in run if s["state"] == "current"), None)
    parts = [f"Offboarding email sent to {to_email}."]
    if summary["it_notified"]:
        parts.append("IT has been notified.")
    if summary["exit_interview"]:
        parts.append(f"Exit interview booked for {summary['exit_interview']['date']} "
                     f"at {summary['exit_interview']['start_time']}.")
    if summary["warning"]:
        parts.append(summary["warning"])
    return jsonify({"message": " ".join(parts), "current_step": current["label"] if current else None}), 200


# ---------- Lifecycle Insights (onboarding + offboarding monitoring) ----------
#
# Feeds the HR "Lifecycle Insights" tab: one flat list covering everyone who
# is currently onboarding OR offboarding, with the display fields (name, id,
# department, photo), real progress, the step they're stuck on, and a
# status. The status comes from _lifecycle_status below - plain, explainable
# rules for now. It is deliberately the ONE place that decides
# on_track / at_risk / delayed, so a trained model can replace it later
# without the endpoint or the UI changing shape.

# Onboarding: days since HR clicked Start.
ONBOARDING_DELAYED_AFTER_DAYS = 7
ONBOARDING_AT_RISK_AFTER_DAYS = 3
ONBOARDING_AT_RISK_BELOW_PERCENT = 50
# Offboarding: days left until the last working day.
OFFBOARDING_AT_RISK_WITHIN_DAYS = 3


def _offboarding_checklist(employee_doc):
    """The employee-facing offboarding checklist (the single place the
    employee screen, HR's profile view, the history panel and Lifecycle
    Insights all read), returned as (items, progress_percent). Its two real
    work items are computed live from the same conditions the flow engine
    uses, so the checklist and the flow chart can never disagree."""
    status = employee_doc.get("offboarding_status") or _default_offboarding_status()
    employee_id = employee_doc["employee_id"]
    interview = _exit_interview_booking(employee_id)
    items = [
        {"id": "departure_recorded", "label": "Departure Recorded",
         "done": True, "done_at": status.get("started_at")},
        {"id": "exit_interview", "label": "Exit Interview",
         "done": bool(status.get("exit_interview_scheduled")) or bool(interview),
         "done_at": status.get("exit_interview_scheduled_at"),
         "meeting": _booking_summary(interview)},
        {"id": "equipment_returned", "label": "Equipment Returned",
         "done": _equipment_return_done(employee_id), "done_at": None},
        {"id": "access_revoked", "label": "IT Access Revoked",
         "done": status.get("access_revoked", False), "done_at": status.get("access_revoked_at")},
    ]
    items += _flow_checklist_items(employee_id, "offboarding", include_documents=True)
    completed = sum(1 for i in items if i["done"])
    return items, round(completed / len(items) * 100)


def _parse_iso(value):
    """ISO string (with or without timezone) -> aware datetime, or None."""
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(value)
    except (TypeError, ValueError):
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def _lifecycle_status(process, progress_percent, days_elapsed, days_to_last_day, current_step):
    """(status, reason) for one onboarding/offboarding record. status is one
    of completed | on_track | at_risk | delayed."""
    if progress_percent >= 100:
        return "completed", "All steps done."

    if process == "onboarding":
        if days_elapsed is not None and days_elapsed > ONBOARDING_DELAYED_AFTER_DAYS:
            return "delayed", f"{days_elapsed} days in, still waiting on: {current_step}."
        if (days_elapsed is not None and days_elapsed >= ONBOARDING_AT_RISK_AFTER_DAYS
                and progress_percent < ONBOARDING_AT_RISK_BELOW_PERCENT):
            return "at_risk", f"{days_elapsed} days in and only {progress_percent}% done - next: {current_step}."
        return "on_track", f"Next: {current_step}."

    if days_to_last_day is not None:
        if days_to_last_day < 0:
            return "delayed", f"Last working day passed {-days_to_last_day} day(s) ago - pending: {current_step}."
        if days_to_last_day <= OFFBOARDING_AT_RISK_WITHIN_DAYS:
            return "at_risk", f"{days_to_last_day} day(s) to last working day - pending: {current_step}."
    return "on_track", f"Next: {current_step}."


def _lifecycle_records():
    now = datetime.now(timezone.utc)
    today = now.date()
    docs = users.find({"role": "employee", "$or": [
        {"onboarding_status.started": True},
        {"offboarding_status.started": True},
    ]})

    records = []
    for d in docs:
        for process in ("onboarding", "offboarding"):
            status_doc = d.get(f"{process}_status") or {}
            if not status_doc.get("started"):
                continue

            if process == "onboarding":
                items, progress = _onboarding_checklist(d)
            else:
                items, progress = _offboarding_checklist(d)

            started_at = _parse_iso(status_doc.get("started_at"))
            days_elapsed = (now - started_at).days if started_at else None

            days_to_last_day = None
            if process == "offboarding" and status_doc.get("last_working_day"):
                try:
                    last_day = datetime.strptime(status_doc["last_working_day"], "%Y-%m-%d").date()
                    days_to_last_day = (last_day - today).days
                except ValueError:
                    pass

            pending = next((i["label"] for i in items if not i["done"]), None)
            status, reason = _lifecycle_status(process, progress, days_elapsed, days_to_last_day, pending)
            completed_at = status_doc.get("completed_at") if status_doc.get("completed") else None
            if completed_at:
                status, reason = "completed", f"Completed on {completed_at[:10]}."
            elif status == "completed":
                # the checklist is full, but the flow still has open steps (custom steps, surveys...)
                status = "on_track"
                reason = f"Waiting on: {_first_open_flow_step(d, process) or 'the last steps'}."

            flow_items = _flow_items_for(d["employee_id"])
            rec_docs = [x for x in flow_items["documents"] if x["process"] == process]
            rec_surveys = [x for x in flow_items["surveys"] if x["process"] == process]
            open_docs = [x for x in rec_docs if (x["action"] == "acknowledge" and x["status"] != "acknowledged")
                         or (x["action"] == "upload" and x["status"] != "approved")]
            open_surveys = [x for x in rec_surveys if x["status"] != "submitted"]
            if open_docs:
                reason += f" Documents: {len(rec_docs) - len(open_docs)} of {len(rec_docs)} complete."
            if open_surveys:
                reason += f" Survey not answered yet ({len(open_surveys)})."

            records.append({
                "employee_id": d["employee_id"],
                "full_name": d["full_name"],
                "department": d.get("department"),
                "job_title": d.get("job_title"),
                "profile_image_url": d.get("profile_image_url"),
                "process": process,
                "started_at": status_doc.get("started_at"),
                "days_elapsed": days_elapsed,
                "progress_percent": progress,
                "steps": items,
                "documents": rec_docs,
                "surveys": rec_surveys,
                "completed_at": completed_at,
                "login_status": _login_status_text(d) if process == "offboarding" else None,
                "current_step": pending,
                "status": status,
                "status_reason": reason,
                "departure_type": status_doc.get("departure_type"),
                "last_working_day": status_doc.get("last_working_day"),
                "days_to_last_day": days_to_last_day,
            })

    severity = {"delayed": 0, "at_risk": 1, "on_track": 2, "completed": 3}
    records.sort(key=lambda r: (severity[r["status"]], r["full_name"].lower()))
    return records


@app.get("/api/hr/dashboard")
@require_hr
def hr_dashboard():
    """Everything HR's dashboard shows, in one call: headcount, who is
    onboarding / offboarding and how far along (the progress tracker, from
    the same _lifecycle_records Lifecycle Insights uses), what is waiting on
    HR, the next week's sessions, and equipment / message counts."""
    emps = list(users.find({"role": "employee"}))
    today = _today_my()
    month_key = today.strftime("%Y-%m")

    by_department, by_work = {}, {}
    for e in emps:
        dept = e.get("department") or "Unassigned"
        by_department[dept] = by_department.get(dept, 0) + 1
        work = e.get("work_location_type") or "Not set"
        by_work[work] = by_work.get(work, 0) + 1
    new_this_month = sum(1 for e in emps if (e.get("hire_date") or "")[:7] == month_key)

    records = _lifecycle_records()

    def summary(process):
        rows = [r for r in records if r["process"] == process]
        return {"total": sum(1 for r in rows if r["status"] != "completed"),
                **{s: sum(1 for r in rows if r["status"] == s)
                                       for s in ("on_track", "at_risk", "delayed", "completed")}}

    # What is waiting on HR right now (the current step of each flow is HR's).
    by_id = {e["employee_id"]: e for e in emps}
    actions = []
    for r in records:
        emp = by_id.get(r["employee_id"])
        if not emp or r["status"] == "completed":
            continue
        run = _onboarding_run(emp) if r["process"] == "onboarding" else _offboarding_run(emp)
        cur = next((s for s in run if s["state"] == "current" and s["kind"] == "hr" and not s.get("waiting")), None)
        if cur:
            label = cur["label"]
            what = f"Send the {'welcome' if r['process'] == 'onboarding' else 'offboarding'} email" \
                if label in ("Send welcome email", "Send offboarding email") else f"Mark “{label}” done"
            actions.append({"employee_id": r["employee_id"], "full_name": r["full_name"],
                            "profile_image_url": r.get("profile_image_url"), "process": r["process"],
                            "action": what, "status": r["status"]})
    severity = {"delayed": 0, "at_risk": 1, "on_track": 2}
    actions.sort(key=lambda a: severity.get(a["status"], 3))

    week_end = (today + timedelta(days=7)).isoformat()
    upcoming = []
    for b in bookings.find({"date": {"$gte": today.isoformat(), "$lte": week_end}}).sort(
            [("date", 1), ("start_time", 1)]).limit(8):
        upcoming.append({"title": b.get("title"), "date": b.get("date"), "start_time": b.get("start_time"),
                         "duration_minutes": b.get("duration_minutes"), "mode": b.get("mode") or "in_person",
                         "session_type": b.get("session_type"), "employee_name": b.get("employee_name"),
                         "attendee_count": len(b.get("attendees") or []),
                         "meeting_url": b.get("meeting_url") or ""})

    eq = {s: equipment.count_documents({"status": s}) for s in ("available", "assigned", "under_repair")}

    # New hires whose approved equipment isn't all assigned yet.
    waiting = []
    for e in emps:
        if not (e.get("onboarding_status") or {}).get("started") or not e.get("equipment_needed"):
            continue
        items, _extra, ready, _at = _equipment_fulfilment(e)
        if not ready:
            waiting.append({"employee_id": e["employee_id"], "full_name": e.get("full_name"),
                            "profile_image_url": e.get("profile_image_url"),
                            "assigned": sum(1 for i in items if i["assigned"]), "needed": len(items)})
    unread = sum(r["unread_count"] for r in _staff_inbox("hr", "hr_thread_read_by_hr_at"))

    return jsonify({
        "headcount": {"total": len(emps), "new_this_month": new_this_month,
                      "by_department": by_department, "by_work_location": by_work},
        "onboarding": summary("onboarding"),
        "offboarding": summary("offboarding"),
        "in_progress": [{k: r.get(k) for k in ("employee_id", "full_name", "department", "profile_image_url",
                                                "process", "progress_percent", "current_step", "status",
                                                "status_reason", "days_elapsed", "last_working_day",
                                                "days_to_last_day")}
                        for r in records if r["status"] != "completed"],
        "actions": actions[:8],
        "upcoming_sessions": upcoming,
        "equipment": eq,
        "equipment_waiting": waiting,
        "unread_messages": unread,
    }), 200


@app.get("/api/it/dashboard")
@require_it
def it_dashboard():
    """Everything IT's dashboard shows, in one call: equipment in stock and
    with people, the work queue (new hires to prepare, leavers to collect
    from - most urgent first, from the same live tasks as the request
    cards), parcels, the week's sessions, warranties ending soon and unread
    employee messages."""
    today = _today_my()
    statuses = {s: equipment.count_documents({"status": s}) for s in ("available", "assigned", "under_repair", "lost")}
    total = equipment.count_documents({})
    holders = len([x for x in equipment.distinct("assigned_to_employee_id", {"status": "assigned"}) if x])

    by_type = {}
    for e in equipment.find({}, {"type": 1, "status": 1}):
        t = e.get("type") or "Other"
        row = by_type.setdefault(t, {"total": 0, "available": 0})
        row["total"] += 1
        row["available"] += 1 if e.get("status") == "available" else 0

    queue = []
    for kind in ("equipment_request", "equipment_return_request"):
        for req in messages.find({"target_role": "it", "kind": kind, "request_status": "open"}):
            emp = users.find_one({"employee_id": req["employee_id"], "role": "employee"})
            if not emp:
                continue
            onboarding = kind == "equipment_request"
            if onboarding:
                tasks, done = _it_onboarding_tasks(emp)
                items, _x, _r, _a = _equipment_fulfilment(emp)
                got, total_items = sum(1 for i in items if i["assigned"]), len(items)
                deadline = _as_date(emp.get("hire_date"))
            else:
                ret_items = _return_items(emp)
                tasks, done = _it_return_tasks(emp, req, ret_items)
                got, total_items = sum(1 for i in ret_items if i["returned"]), len(ret_items)
                deadline = _as_date((emp.get("offboarding_status") or {}).get("last_working_day"))
            if done:
                continue
            days_left = (deadline - today).days if deadline else None
            nxt = next((t for t in tasks if not t["done"]), None)
            queue.append({
                "employee_id": emp["employee_id"], "full_name": emp.get("full_name"),
                "profile_image_url": emp.get("profile_image_url"), "department": emp.get("department"),
                "work_location_type": emp.get("work_location_type"),
                "process": "onboarding" if onboarding else "offboarding",
                "done_count": got, "total_count": total_items,
                "next_task": f"{nxt['label']} ({nxt['detail']})" if nxt else "",
                "deadline": deadline.isoformat() if deadline else None, "days_left": days_left,
                "status": "overdue" if days_left is not None and days_left < 0
                else "due_soon" if days_left is not None and days_left <= 3 else "on_track",
            })
    queue.sort(key=lambda q: (q["days_left"] if q["days_left"] is not None else 9999))

    def count_parcels(direction, statuses_in):
        return shipments.count_documents({"direction": direction, "status": {"$in": statuses_in}})
    parcels = {
        "to_create": count_parcels("to_employee", ["pending"]),
        "to_post": count_parcels("to_employee", ["order_created"]),
        "on_the_way": count_parcels("to_employee", ["dropped_off"]),
        "returns_to_review": shipments.count_documents({"direction": "return", "status": "dropped_off",
                                                         "submitted_by_employee": True}),
        "returns_on_the_way": shipments.count_documents({"direction": "return", "status": "dropped_off",
                                                          "submitted_by_employee": {"$ne": True}}),
    }

    week_end = (today + timedelta(days=7)).isoformat()
    upcoming = [{"title": b.get("title"), "date": b.get("date"), "start_time": b.get("start_time"),
                 "duration_minutes": b.get("duration_minutes"), "mode": b.get("mode") or "in_person",
                 "employee_name": b.get("employee_name"), "attendee_count": len(b.get("attendees") or [])}
                for b in bookings.find({"date": {"$gte": today.isoformat(), "$lte": week_end}}).sort(
                    [("date", 1), ("start_time", 1)]).limit(8)]

    soon = (today + timedelta(days=90)).isoformat()
    warranties = []
    for e in equipment.find({"warranty_expiry": {"$gte": today.isoformat(), "$lte": soon + "T23:59:59"},
                             "status": {"$ne": "lost"}}).sort("warranty_expiry", 1).limit(6):
        ends = _as_date(e.get("warranty_expiry"))
        warranties.append({"equipment_id": str(e["_id"]), "name": e.get("name"), "type": e.get("type"),
                           "asset_tag": e.get("asset_tag") or "", "photo_url": e.get("photo_url"),
                           "warranty_expiry": ends.isoformat() if ends else None,
                           "days_left": (ends - today).days if ends else None,
                           "assigned_to": e.get("assigned_to_employee_name")})

    unread = sum(r["unread_count"] for r in _staff_inbox("it", "it_thread_read_by_it_at"))
    return jsonify({
        "equipment": {"total": total, **statuses, "holders": holders, "by_type": by_type},
        "queue": queue,
        "new_hires_open": sum(1 for q in queue if q["process"] == "onboarding"),
        "returns_open": sum(1 for q in queue if q["process"] == "offboarding"),
        "parcels": parcels,
        "upcoming_sessions": upcoming,
        "warranties": warranties,
        "unread_messages": unread,
    }), 200


@app.get("/api/lifecycle/overview")
@require_hr
def lifecycle_overview():
    records = _lifecycle_records()

    def count(process, status=None):
        return sum(1 for r in records
                   if r["process"] == process and (status is None or r["status"] == status))

    summary = {
        # people still in progress (completed ones are counted under "completed")
        "onboarding_total": sum(1 for r in records if r["process"] == "onboarding" and r["status"] != "completed"),
        "offboarding_total": sum(1 for r in records if r["process"] == "offboarding" and r["status"] != "completed"),
        "on_track": sum(1 for r in records if r["status"] == "on_track"),
        "at_risk": sum(1 for r in records if r["status"] == "at_risk"),
        "delayed": sum(1 for r in records if r["status"] == "delayed"),
        "completed": sum(1 for r in records if r["status"] == "completed"),
    }
    return jsonify({"summary": summary, "records": records}), 200


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

# The core onboarding flow, in order. These can't be deleted (the builder
# shows a lock instead of a delete button, and the server re-adds any that
# go missing on every read/save), but HR can add their own steps around
# them with "+". Labels matter: the auto-start automation looks steps up
# by label ("Schedule orientation", "Prepare IT equipment").
PREPARE_LAPTOP_SUB = "Asks IT, then waits for the equipment"
LOCKED_ONBOARDING_STEPS = (
    "Send welcome email",
    "Prepare IT equipment",
    "Schedule orientation",
)
# Only part of a flow for remote employees (equipment is posted
# to them); onsite employees collect theirs, so it's left out.
COURIER_STEP = "Arrange courier"
# Older versions had this step; it's stripped from every flow.
RETIRED_ONBOARDING_STEPS = (
    # Now part of "Prepare IT equipment", which asks IT itself.
    "Notify IT",
    "Work location",
    # The old default branch (onsite -> prepare laptop / remote -> courier).
    # Its steps now sit in the main flow, so the branch itself is dropped.
    "Condition — work location type",
)


def _locked_step_node(label):
    spec = {
        "Send welcome email": {"icon": "ti-mail", "sub": "AI-drafted, then sent"},
        "Notify IT": {"icon": "ti-message-circle", "sub": "Equipment request and account details to IT"},
        "Prepare IT equipment": {"icon": "ti-device-laptop", "sub": PREPARE_LAPTOP_SUB},
        COURIER_STEP: {"icon": "ti-truck-delivery", "sub": "Remote — posted via Pos Malaysia"},
        "Schedule orientation": {"icon": "ti-calendar", "sub": "Auto-assigned slot"},
        END_ONBOARDING: {"icon": "ti-flag", "sub": "Done when everything above is done"},
    }[label]
    return {"id": str(uuid.uuid4()), "type": "action", "label": label, "locked": True, **spec}


def _default_documents_node():
    """HR fills in the actual documents (and attaches the files) by clicking the step."""
    return {"id": str(uuid.uuid4()), "type": "action", "icon": "ti-file-text", "label": "Documents",
            "sub": "No documents yet - click edit to add them", "step": "documents", "docs": [],
            "key": "default_documents", "locked": True}


def _default_survey_node(process="onboarding"):
    if process == "offboarding":
        title, questions = "Offboarding check-in", [
            {"id": "q1", "text": "How would you rate your overall time with us?", "type": "rating"},
            {"id": "q2", "text": "Would you recommend us as a place to work?", "type": "yes_no"},
            {"id": "q3", "text": "Anything we could have done better?", "type": "text"},
        ]
    else:
        title, questions = "Onboarding check-in", [
            {"id": "q1", "text": "How is your onboarding going so far?", "type": "rating"},
            {"id": "q2", "text": "Do you have everything you need to start?", "type": "yes_no"},
            {"id": "q3", "text": "Anything we should know or improve?", "type": "text"},
        ]
    return {"id": str(uuid.uuid4()), "type": "action", "icon": "ti-clipboard-list", "key": "default_survey", "locked": True,
            "label": f"Survey: {title}", "sub": f"{len(questions)} questions", "step": "survey",
            "survey": {"title": title, "questions": questions}}


def _default_flow_nodes():
    """Welcome email, Documents, IT equipment, orientation, check-in survey, End.
    (The flow starts right under the employee picker - there is no separate
    "Employee details inserted" step any more.)"""
    return [
        _locked_step_node("Send welcome email"),
        _default_documents_node(),
        _locked_step_node("Prepare IT equipment"),
        _locked_step_node("Schedule orientation"),
        _default_survey_node(),
        _locked_step_node(END_ONBOARDING),
    ]


def _drop_trigger(nodes):
    """Removes the old "Employee details inserted" step (id "trigger") from
    flows saved before it was retired. Returns True if one was removed."""
    before = len(nodes)
    nodes[:] = [n for n in nodes if n.get("id") != "trigger"]
    return len(nodes) != before


def _normalize_onboarding_nodes(nodes, work_location=None):
    """Makes sure the required steps exist and are locked, drops retired
    ones, and adds/removes the courier step to match the employee's work
    location - leaving every custom step exactly where HR put it.
    work_location is None for the shared template (never has a courier).
    Returns (nodes, changed)."""
    changed = False
    needs_courier = work_location in SHIPPING_WORK_LOCATIONS
    required = list(LOCKED_ONBOARDING_STEPS)
    if needs_courier:
        required.insert(required.index("Schedule orientation"), COURIER_STEP)
    found = set()

    def sweep(lst):
        nonlocal changed
        kept = []
        for n in lst:
            label = n.get("label")
            if label == "Prepare" + " laptop":  # the step's old name
                n["label"] = label = "Prepare IT equipment"
                changed = True
            drop = label in RETIRED_ONBOARDING_STEPS or (label == COURIER_STEP and not needs_courier)
            if drop:
                changed = True
                continue
            if label in required:
                found.add(label)
                if not n.get("locked"):
                    n["locked"] = True
                    changed = True
                if label == "Prepare IT equipment" and n.get("sub") != PREPARE_LAPTOP_SUB:
                    n["sub"] = PREPARE_LAPTOP_SUB
                    changed = True
            if n.get("type") == "condition":
                n["branch_a"] = sweep(n.get("branch_a") or [])
                n["branch_b"] = sweep(n.get("branch_b") or [])
            kept.append(n)
        return kept

    nodes[:] = sweep(nodes)
    changed |= _drop_trigger(nodes)

    for i, label in enumerate(required):
        if label in found:
            continue
        # Re-insert right after the nearest earlier required step that is
        # still present at the top level; otherwise at the very start.
        insert_at = 0
        for earlier in required[:i]:
            for idx, n in enumerate(nodes):
                if n.get("label") == earlier:
                    insert_at = idx + 1
        nodes.insert(min(insert_at, len(nodes)), _locked_step_node(label))
        found.add(label)
        changed = True

    # The default Documents and Survey steps can be edited but never deleted.
    for key, factory in (("default_documents", _default_documents_node), ("default_survey", _default_survey_node)):
        existing = next((n for n in nodes if n.get("key") == key), None)
        if existing is None:
            if key == "default_documents":
                at = next((i for i, n in enumerate(nodes) if n.get("label") == "Send welcome email"), -1) + 1
                nodes.insert(at, factory())
            else:
                nodes.append(factory())  # the End step is moved back below it just after
            changed = True
        elif not existing.get("locked"):
            existing["locked"] = True
            changed = True

    # The End step always closes the flow.
    end_at = next((i for i, n in enumerate(nodes) if n.get("label") == END_ONBOARDING), None)
    if end_at is None:
        nodes.append(_locked_step_node(END_ONBOARDING))
        changed = True
    else:
        if end_at != len(nodes) - 1:
            nodes.append(nodes.pop(end_at))
            changed = True
        if not nodes[-1].get("locked"):
            nodes[-1]["locked"] = True
            changed = True
    return nodes, changed


@app.get("/api/onboarding-flows/template")
@require_hr
def get_flow_template():
    doc = onboarding_flows.find_one({"_id": "template"})
    if not doc:
        doc = {"_id": "template", "nodes": _default_flow_nodes()}
        onboarding_flows.insert_one(doc)
    nodes, changed = _normalize_onboarding_nodes(doc["nodes"])
    if changed:
        onboarding_flows.update_one({"_id": "template"}, {"$set": {"nodes": nodes}})
    return jsonify({"nodes": nodes}), 200


@app.put("/api/onboarding-flows/template")
@require_hr
def save_flow_template():
    nodes = (request.get_json(silent=True) or {}).get("nodes")
    if not isinstance(nodes, list):
        return jsonify({"message": "nodes must be a list."}), 400
    nodes, _ = _normalize_onboarding_nodes(nodes)
    onboarding_flows.update_one({"_id": "template"}, {"$set": {"nodes": nodes}}, upsert=True)
    return jsonify({"message": "Template saved."}), 200


def _employee_flow_nodes(employee_id):
    """Shared by the flow-builder routes and the auto-start automation
    below — same copy-on-first-open logic either way, so reading an
    employee's flow never produces a different answer depending on which
    endpoint asked."""
    doc = onboarding_flows.find_one({"_id": employee_id})
    if not doc:
        template = onboarding_flows.find_one({"_id": "template"})
        nodes = template["nodes"] if template else _default_flow_nodes()
        doc = {"_id": employee_id, "nodes": nodes}
        onboarding_flows.insert_one(doc)
    emp = users.find_one({"employee_id": employee_id, "role": "employee"}) or {}
    nodes, changed = _normalize_onboarding_nodes(doc["nodes"], emp.get("work_location_type"))
    if changed:
        onboarding_flows.update_one({"_id": employee_id}, {"$set": {"nodes": nodes}})
    return nodes


def _flow_node_labels(nodes):
    """Flattened set of every node's label in this flow, including ones
    nested inside condition branches, so a step can be looked up by name
    regardless of where HR placed it in the diagram."""
    labels = set()
    for n in nodes:
        labels.add(n.get("label"))
        if n.get("type") == "condition":
            labels |= _flow_node_labels(n.get("branch_a") or [])
            labels |= _flow_node_labels(n.get("branch_b") or [])
    return labels


@app.get("/api/onboarding-flows/employee/<employee_id>")
@require_hr
def get_employee_flow(employee_id):
    emp = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not emp:
        return jsonify({"message": "Employee not found."}), 404

    return jsonify({"nodes": _employee_flow_nodes(employee_id)}), 200


@app.put("/api/onboarding-flows/employee/<employee_id>")
@require_hr
def save_employee_flow(employee_id):
    emp = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not emp:
        return jsonify({"message": "Employee not found."}), 404

    nodes = (request.get_json(silent=True) or {}).get("nodes")
    if not isinstance(nodes, list):
        return jsonify({"message": "nodes must be a list."}), 400
    nodes, _ = _normalize_onboarding_nodes(nodes, emp.get("work_location_type"))
    onboarding_flows.update_one({"_id": employee_id}, {"$set": {"nodes": nodes}}, upsert=True)
    _advance_safely(employee_id)  # if onboarding is already running, a new step starts now
    return jsonify({"message": "Flow saved."}), 200


# --- Offboarding automation flow builder ---
#
# Same template/per-employee-copy pattern as onboarding, in its own
# collection so the two never collide. Default steps map onto the report's
# 5-phase offboarding process (2.1.3): notification, exit interview,
# knowledge transfer, paperwork, IT access & security.

# The offboarding flow: only these steps, in this order, all locked (the
# builder shows a lock, and the server re-adds any that go missing on every
# read/save). HR can still add their own steps around them with "+".
RETRIEVE_EQUIPMENT_SUB = "Asks IT, then waits for the return"
LOCKED_OFFBOARDING_STEPS = (
    "Send offboarding email",
    "Retrieve IT equipment",
    "Schedule exit interview",
)
# Steps from earlier versions of the default flow - stripped everywhere.
RETIRED_OFFBOARDING_STEPS = (
    # Now part of "Retrieve IT equipment", which asks IT itself.
    "Notify IT",
    "Notify manager & HR",
    "Knowledge transfer checklist",
    "Finalize payroll & benefits",
    "Revoke system access",
)


def _offboarding_step_node(label):
    spec = {
        "Send offboarding email": {"icon": "ti-mail", "sub": "Tell the employee about their offboarding"},
        "Retrieve IT equipment": {"icon": "ti-qrcode", "sub": RETRIEVE_EQUIPMENT_SUB},
        "Schedule exit interview": {"icon": "ti-calendar", "sub": "Auto-assigned slot"},
        END_OFFBOARDING: {"icon": "ti-flag", "sub": "Done when everything above is done"},
    }[label]
    return {"id": str(uuid.uuid4()), "type": "action", "label": label, "locked": True, **spec}


def _default_offboarding_nodes():
    """Offboarding email, Documents, IT equipment, exit interview, check-in
    survey, End."""
    return [
        _offboarding_step_node("Send offboarding email"),
        _default_documents_node(),
        _offboarding_step_node("Retrieve IT equipment"),
        _offboarding_step_node("Schedule exit interview"),
        _default_survey_node("offboarding"),
        _offboarding_step_node(END_OFFBOARDING),
    ]


def _normalize_offboarding_nodes(nodes):
    """Keeps the offboarding flow to its core: strips retired steps, marks the core steps locked and re-adds any that are
    missing - leaving every step HR added exactly where it was.
    Returns (nodes, changed)."""
    changed = False
    found = set()

    def sweep(lst):
        nonlocal changed
        kept = []
        for n in lst:
            label = n.get("label")
            if label in RETIRED_OFFBOARDING_STEPS:
                changed = True
                continue
            if label in LOCKED_OFFBOARDING_STEPS:
                found.add(label)
                if not n.get("locked"):
                    n["locked"] = True
                    changed = True
                if label == "Retrieve IT equipment" and n.get("sub") != RETRIEVE_EQUIPMENT_SUB:
                    n["sub"] = RETRIEVE_EQUIPMENT_SUB
                    changed = True
            if n.get("type") == "condition":
                n["branch_a"] = sweep(n.get("branch_a") or [])
                n["branch_b"] = sweep(n.get("branch_b") or [])
            kept.append(n)
        return kept

    nodes[:] = sweep(nodes)
    changed |= _drop_trigger(nodes)
    for i, label in enumerate(LOCKED_OFFBOARDING_STEPS):
        if label in found:
            continue
        insert_at = 0
        for earlier in LOCKED_OFFBOARDING_STEPS[:i]:
            for idx, n in enumerate(nodes):
                if n.get("label") == earlier:
                    insert_at = idx + 1
        nodes.insert(min(insert_at, len(nodes)), _offboarding_step_node(label))
        found.add(label)
        changed = True

    # The default Documents and Survey steps can be edited but never deleted.
    for key, factory in (("default_documents", _default_documents_node),
                         ("default_survey", lambda: _default_survey_node("offboarding"))):
        existing = next((n for n in nodes if n.get("key") == key), None)
        if existing is None:
            if key == "default_documents":
                at = next((i for i, n in enumerate(nodes) if n.get("label") == "Send offboarding email"), -1) + 1
                nodes.insert(at, factory())
            else:
                nodes.append(factory())  # the End step is moved back below it just after
            changed = True
        elif not existing.get("locked"):
            existing["locked"] = True
            changed = True

    # The End step always closes the flow.
    end_at = next((i for i, n in enumerate(nodes) if n.get("label") == END_OFFBOARDING), None)
    if end_at is None:
        nodes.append(_offboarding_step_node(END_OFFBOARDING))
        changed = True
    else:
        if end_at != len(nodes) - 1:
            nodes.append(nodes.pop(end_at))
            changed = True
        if not nodes[-1].get("locked"):
            nodes[-1]["locked"] = True
            changed = True
    return nodes, changed


@app.get("/api/offboarding-flows/template")
@require_hr
def get_offboarding_flow_template():
    doc = offboarding_flows.find_one({"_id": "template"})
    if not doc:
        doc = {"_id": "template", "nodes": _default_offboarding_nodes()}
        offboarding_flows.insert_one(doc)
    nodes, changed = _normalize_offboarding_nodes(doc["nodes"])
    if changed:
        offboarding_flows.update_one({"_id": "template"}, {"$set": {"nodes": nodes}})
    return jsonify({"nodes": nodes}), 200


@app.put("/api/offboarding-flows/template")
@require_hr
def save_offboarding_flow_template():
    nodes = (request.get_json(silent=True) or {}).get("nodes")
    if not isinstance(nodes, list):
        return jsonify({"message": "nodes must be a list."}), 400
    nodes, _ = _normalize_offboarding_nodes(nodes)
    offboarding_flows.update_one({"_id": "template"}, {"$set": {"nodes": nodes}}, upsert=True)
    return jsonify({"message": "Template saved."}), 200


def _offboarding_flow_nodes(employee_id):
    """Shared by the flow-builder route and the offboarding engine - same
    copy-on-first-open logic either way, so reading an employee's flow never
    gives a different answer depending on who asked."""
    doc = offboarding_flows.find_one({"_id": employee_id})
    if not doc:
        template = offboarding_flows.find_one({"_id": "template"})
        nodes = template["nodes"] if template else _default_offboarding_nodes()
        doc = {"_id": employee_id, "nodes": nodes}
        offboarding_flows.insert_one(doc)
    nodes, changed = _normalize_offboarding_nodes(doc["nodes"])
    if changed:
        offboarding_flows.update_one({"_id": employee_id}, {"$set": {"nodes": nodes}})
    return nodes


@app.get("/api/offboarding-flows/employee/<employee_id>")
@require_hr
def get_offboarding_employee_flow(employee_id):
    emp = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not emp:
        return jsonify({"message": "Employee not found."}), 404

    return jsonify({"nodes": _offboarding_flow_nodes(employee_id)}), 200


@app.put("/api/offboarding-flows/employee/<employee_id>")
@require_hr
def save_offboarding_employee_flow(employee_id):
    emp = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not emp:
        return jsonify({"message": "Employee not found."}), 404

    nodes = (request.get_json(silent=True) or {}).get("nodes")
    if not isinstance(nodes, list):
        return jsonify({"message": "nodes must be a list."}), 400
    nodes, _ = _normalize_offboarding_nodes(nodes)
    offboarding_flows.update_one({"_id": employee_id}, {"$set": {"nodes": nodes}}, upsert=True)
    _advance_offboarding_safely(employee_id)  # if offboarding is already running, a new step starts now
    return jsonify({"message": "Flow saved."}), 200


# ---------- Flow steps that involve the employee: Documents and Survey ----------
#
# Two step types HR can add behind a "+" in the onboarding or offboarding
# flow. Their set-up lives on the flow node itself:
#   Documents: node["step"] == "documents", node["docs"] = [{id, title,
#              action ("download" | "acknowledge" | "upload"), instructions,
#              file_id, filename}]
#   Survey:    node["step"] == "survey", node["survey"] = {title,
#              questions: [{id, text, type ("rating" | "yes_no" | "text")}]}
# When the flow reaches the step, a copy is issued to the employee (so later
# edits to the flow never change what they were given) and the step is done
# once the employee has done their part (and HR has approved uploads).
#
# Files are kept in PRIVATE_FOLDER, which is NOT served as static files: they
# only leave through the authenticated routes below, and only HR and the one
# employee they belong to can fetch them (never IT, never other employees,
# and they are not part of the company library the chatbots read).

PRIVATE_FOLDER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "private_files")
os.makedirs(PRIVATE_FOLDER, exist_ok=True)
MAX_FLOW_FILE_BYTES = 10 * 1024 * 1024
FLOW_ATTACH_EXTENSIONS = {"pdf", "doc", "docx", "xls", "xlsx", "png", "jpg", "jpeg", "txt"}
FLOW_RETURN_EXTENSIONS = {"pdf", "doc", "docx", "png", "jpg", "jpeg"}
FLOW_DOC_ACTIONS = ("download", "upload")
EMPLOYEE_STEP_TYPES = ("documents", "survey")

flow_files = db["flow_files"]          # files HR attached to a Documents step
flow_documents = db["flow_documents"]  # one row per document issued to an employee
flow_surveys = db["flow_surveys"]      # one row per survey issued to an employee


def _flow_doc_complete(rec):
    """Has the employee (and HR, for uploads) finished with this document?"""
    action = rec.get("action")
    if action == "acknowledge":
        return rec.get("status") == "acknowledged"
    if action == "upload":
        return rec.get("status") == "approved"
    return True  # download only: nothing to do once it has been issued


def _custom_step_done(emp, node, process):
    eid = emp["employee_id"]
    step = node.get("step")
    if step == "documents":
        recs = {r["doc_id"]: r for r in flow_documents.find(
            {"employee_id": eid, "process": process, "step_id": node["id"]})}
        for d in node.get("docs") or []:
            rec = recs.get(d.get("id"))
            if rec is None or not _flow_doc_complete(rec):
                return False
        return True
    if step == "survey":
        return bool(flow_surveys.find_one({"employee_id": eid, "process": process,
                                           "step_id": node["id"], "status": "submitted"}))
    return False


def _custom_step_hint(emp, node, process):
    eid = emp["employee_id"]
    if node.get("step") == "documents":
        docs = node.get("docs") or []
        done = sum(1 for d in docs if (r := flow_documents.find_one(
            {"employee_id": eid, "process": process, "step_id": node["id"], "doc_id": d.get("id")}))
            and _flow_doc_complete(r))
        return f"Waiting on the employee's documents ({done} of {len(docs)} complete)."
    return "Waiting for the employee to answer the survey."


def _issue_flow_step(emp, node, process):
    """Hands the step's documents / survey to the employee (once)."""
    eid = emp["employee_id"]
    now = datetime.now(timezone.utc).isoformat()
    step = node.get("step")
    if step == "documents":
        titles = []
        for d in node.get("docs") or []:
            key = {"employee_id": eid, "process": process, "step_id": node["id"], "doc_id": d.get("id")}
            if flow_documents.find_one(key):
                continue
            # Two kinds only: download, or download and upload back (older "acknowledge" = download)
            action = "upload" if d.get("action") == "upload" else "download"
            flow_documents.insert_one({
                **key, "title": (d.get("title") or "Document").strip(), "action": action,
                "instructions": (d.get("instructions") or "").strip(),
                "file_id": d.get("file_id"), "filename": d.get("filename"),
                "status": "sent", "created_at": now,
            })
            titles.append(d.get("title") or "Document")
        if titles:
            _notify("employee", eid, "notification", "New documents from HR",
                    ", ".join(titles) + ". Open the Documents tab.", {"type": "documents"})
    elif step == "survey":
        key = {"employee_id": eid, "process": process, "step_id": node["id"]}
        if not flow_surveys.find_one(key):
            survey = node.get("survey") or {}
            flow_surveys.insert_one({
                **key, "title": (survey.get("title") or node.get("label") or "Survey").strip(),
                "questions": survey.get("questions") or [], "status": "open", "created_at": now,
            })
            _notify("employee", eid, "notification", "A short survey from HR",
                    (survey.get("title") or "Survey") + ". Open the Documents tab.", {"type": "documents"})


def _advance_flow(employee_id, process):
    (_advance_safely if process == "onboarding" else _advance_offboarding_safely)(employee_id)


def _clear_flow_items(employee_id, process=None):
    """Removes what was issued to an employee, including the files they
    uploaded - used when a flow is cancelled or the employee is deleted."""
    query = {"employee_id": employee_id}
    if process:
        query["process"] = process
    for rec in flow_documents.find(query):
        returned = rec.get("returned_stored_name")
        if returned:
            try:
                os.remove(os.path.join(PRIVATE_FOLDER, returned))
            except OSError:
                pass
    flow_documents.delete_many(query)
    flow_surveys.delete_many(query)


def _flow_items_badge(employee_id, seen_documents):
    """What still needs the employee's attention in the Documents tab."""
    n = 0
    for r in flow_documents.find({"employee_id": employee_id}):
        if r.get("action") in ("acknowledge", "upload"):
            if r.get("status") in ("sent", "rejected"):
                n += 1
        elif not seen_documents or r.get("created_at", "") > seen_documents:
            n += 1
    return n + flow_surveys.count_documents({"employee_id": employee_id, "status": "open"})


def _flow_doc_public(r):
    return {
        "id": str(r["_id"]), "process": r.get("process"), "title": r.get("title"),
        "action": r.get("action"), "instructions": r.get("instructions") or "",
        "status": r.get("status"), "has_file": bool(r.get("file_id")), "filename": r.get("filename"),
        "returned_filename": r.get("returned_filename"), "returned_at": r.get("returned_at"),
        "reject_reason": r.get("reject_reason"), "approved_at": r.get("approved_at"),
        "acknowledged_at": r.get("acknowledged_at"), "created_at": r.get("created_at"),
    }


def _flow_survey_public(r):
    return {
        "id": str(r["_id"]), "process": r.get("process"), "title": r.get("title"),
        "questions": r.get("questions") or [], "status": r.get("status"),
        "answers": r.get("answers") or {}, "submitted_at": r.get("submitted_at"),
        "created_at": r.get("created_at"),
    }


def _flow_items_for(employee_id):
    docs = [_flow_doc_public(r) for r in flow_documents.find({"employee_id": employee_id}).sort("created_at", 1)]
    surveys = [_flow_survey_public(r) for r in flow_surveys.find({"employee_id": employee_id}).sort("created_at", 1)]
    return {"documents": docs, "surveys": surveys}


def _read_flow_upload(allowed):
    """Returns ((filename, ext, bytes), None) or (None, error message)."""
    f = request.files.get("file")
    if f is None or not f.filename:
        return None, "No file was sent."
    ext = f.filename.rsplit(".", 1)[-1].lower() if "." in f.filename else ""
    if ext not in allowed:
        return None, "File type not allowed. Use: " + ", ".join(sorted(allowed)).upper() + "."
    data = f.read()
    if len(data) > MAX_FLOW_FILE_BYTES:
        return None, "That file is too large (10MB maximum)."
    return (f.filename, ext, data), None


def _find_flow_doc(doc_id, employee_id=None):
    try:
        query = {"_id": ObjectId(doc_id)}
    except Exception:  # noqa: BLE001
        return None
    if employee_id:
        query["employee_id"] = employee_id
    return flow_documents.find_one(query)


def _find_flow_survey(survey_id, employee_id=None):
    try:
        query = {"_id": ObjectId(survey_id)}
    except Exception:  # noqa: BLE001
        return None
    if employee_id:
        query["employee_id"] = employee_id
    return flow_surveys.find_one(query)


# ----- HR: attach a file to a Documents step

@app.post("/api/hr/flow-files")
@require_hr
def hr_upload_flow_file():
    upload, error = _read_flow_upload(FLOW_ATTACH_EXTENSIONS)
    if error:
        return jsonify({"message": error}), 400
    filename, ext, data = upload
    file_id = uuid.uuid4().hex
    stored = f"{file_id}.{ext}"
    with open(os.path.join(PRIVATE_FOLDER, stored), "wb") as fh:
        fh.write(data)
    flow_files.insert_one({"_id": file_id, "filename": filename, "stored_name": stored, "size": len(data),
                           "uploaded_by": g.current_user.get("email"),
                           "uploaded_at": datetime.now(timezone.utc).isoformat()})
    return jsonify({"file_id": file_id, "filename": filename}), 200


@app.get("/api/hr/flow-files/<file_id>")
@require_hr
def hr_download_flow_file(file_id):
    rec = flow_files.find_one({"_id": file_id})
    if not rec:
        return jsonify({"message": "File not found."}), 404
    return send_from_directory(PRIVATE_FOLDER, rec["stored_name"], as_attachment=True,
                               download_name=rec["filename"])


# ----- Employee: see, download, acknowledge, upload, answer

@app.get("/api/employee/me/flow-items")
@require_employee
def employee_flow_items():
    return jsonify(_flow_items_for(g.current_employee["employee_id"])), 200


@app.get("/api/employee/me/flow-documents/<doc_id>/file")
@require_employee
def employee_flow_doc_file(doc_id):
    rec = _find_flow_doc(doc_id, g.current_employee["employee_id"])
    meta = flow_files.find_one({"_id": rec.get("file_id")}) if rec and rec.get("file_id") else None
    if not meta:
        return jsonify({"message": "File not found."}), 404
    return send_from_directory(PRIVATE_FOLDER, meta["stored_name"], as_attachment=True,
                               download_name=meta["filename"])


@app.post("/api/employee/me/flow-documents/<doc_id>/acknowledge")
@require_employee
def employee_flow_doc_acknowledge(doc_id):
    rec = _find_flow_doc(doc_id, g.current_employee["employee_id"])
    if not rec:
        return jsonify({"message": "Document not found."}), 404
    if rec.get("action") != "acknowledge":
        return jsonify({"message": "This document doesn't need acknowledging."}), 400
    flow_documents.update_one({"_id": rec["_id"]}, {"$set": {
        "status": "acknowledged", "acknowledged_at": datetime.now(timezone.utc).isoformat()}})
    _notify("hr", None, "notification", f"{g.current_employee['full_name']} acknowledged a document",
            rec.get("title") or "Document", {"type": "lifecycle"})
    _advance_flow(rec["employee_id"], rec.get("process"))
    return jsonify({"message": "Acknowledged."}), 200


@app.post("/api/employee/me/flow-documents/<doc_id>/upload")
@require_employee
def employee_flow_doc_upload(doc_id):
    rec = _find_flow_doc(doc_id, g.current_employee["employee_id"])
    if not rec:
        return jsonify({"message": "Document not found."}), 404
    if rec.get("action") != "upload":
        return jsonify({"message": "This document doesn't need a file back."}), 400
    if rec.get("status") == "approved":
        return jsonify({"message": "HR has already approved this document."}), 400
    upload, error = _read_flow_upload(FLOW_RETURN_EXTENSIONS)
    if error:
        return jsonify({"message": error}), 400
    filename, ext, data = upload
    stored = f"ret-{uuid.uuid4().hex}.{ext}"
    with open(os.path.join(PRIVATE_FOLDER, stored), "wb") as fh:
        fh.write(data)
    old = rec.get("returned_stored_name")
    if old:
        try:
            os.remove(os.path.join(PRIVATE_FOLDER, old))
        except OSError:
            pass
    flow_documents.update_one({"_id": rec["_id"]}, {
        "$set": {"status": "returned", "returned_filename": filename, "returned_stored_name": stored,
                 "returned_at": datetime.now(timezone.utc).isoformat()},
        "$unset": {"reject_reason": ""}})
    _notify("hr", None, "notification", f"{g.current_employee['full_name']} uploaded a document",
            f"{rec.get('title') or 'Document'} is waiting for your review.", {"type": "lifecycle"})
    return jsonify({"message": "Uploaded. HR will review it."}), 200


@app.post("/api/employee/me/surveys/<survey_id>/submit")
@require_employee
def employee_submit_survey(survey_id):
    rec = _find_flow_survey(survey_id, g.current_employee["employee_id"])
    if not rec:
        return jsonify({"message": "Survey not found."}), 404
    if rec.get("status") == "submitted":
        return jsonify({"message": "You already answered this survey."}), 400
    given = (request.get_json(silent=True) or {}).get("answers") or {}
    answers = {}
    for q in rec.get("questions") or []:
        qid, qtype, value = q.get("id"), q.get("type"), given.get(q.get("id"))
        if qtype == "rating":
            try:
                value = int(value)
            except (TypeError, ValueError):
                value = None
            if value is None or not 1 <= value <= 5:
                return jsonify({"message": f"Please rate: {q.get('text')}"}), 400
        elif qtype == "yes_no":
            if value not in ("yes", "no"):
                return jsonify({"message": f"Please answer: {q.get('text')}"}), 400
        else:
            value = str(value or "").strip()[:1000]
        answers[qid] = value
    flow_surveys.update_one({"_id": rec["_id"]}, {"$set": {
        "status": "submitted", "answers": answers, "submitted_at": datetime.now(timezone.utc).isoformat()}})
    _notify("hr", None, "notification", f"{g.current_employee['full_name']} answered a survey",
            rec.get("title") or "Survey", {"type": "lifecycle"})
    _advance_flow(rec["employee_id"], rec.get("process"))
    return jsonify({"message": "Thank you - your answers were sent."}), 200


# ----- HR: review what an employee returned

@app.get("/api/hr/employees/<employee_id>/flow-items")
@require_hr
def hr_employee_flow_items(employee_id):
    return jsonify(_flow_items_for(employee_id)), 200


@app.get("/api/hr/flow-documents/<doc_id>/file")
@require_hr
def hr_flow_doc_file(doc_id):
    rec = _find_flow_doc(doc_id)
    meta = flow_files.find_one({"_id": rec.get("file_id")}) if rec and rec.get("file_id") else None
    if not meta:
        return jsonify({"message": "File not found."}), 404
    return send_from_directory(PRIVATE_FOLDER, meta["stored_name"], as_attachment=True,
                               download_name=meta["filename"])


@app.get("/api/hr/flow-documents/<doc_id>/returned")
@require_hr
def hr_flow_doc_returned(doc_id):
    rec = _find_flow_doc(doc_id)
    if not rec or not rec.get("returned_stored_name"):
        return jsonify({"message": "Nothing has been uploaded yet."}), 404
    return send_from_directory(PRIVATE_FOLDER, rec["returned_stored_name"], as_attachment=True,
                               download_name=rec.get("returned_filename") or rec["returned_stored_name"])


@app.post("/api/hr/flow-documents/<doc_id>/approve")
@require_hr
def hr_flow_doc_approve(doc_id):
    rec = _find_flow_doc(doc_id)
    if not rec:
        return jsonify({"message": "Document not found."}), 404
    if rec.get("status") != "returned":
        return jsonify({"message": "There is nothing waiting for approval."}), 400
    flow_documents.update_one({"_id": rec["_id"]}, {
        "$set": {"status": "approved", "approved_at": datetime.now(timezone.utc).isoformat()},
        "$unset": {"reject_reason": ""}})
    _notify("employee", rec["employee_id"], "notification", "Document approved",
            f"HR approved {rec.get('title') or 'your document'}.", {"type": "documents"})
    _advance_flow(rec["employee_id"], rec.get("process"))
    return jsonify({"message": "Approved."}), 200


@app.post("/api/hr/flow-documents/<doc_id>/reject")
@require_hr
def hr_flow_doc_reject(doc_id):
    rec = _find_flow_doc(doc_id)
    if not rec:
        return jsonify({"message": "Document not found."}), 404
    if rec.get("status") != "returned":
        return jsonify({"message": "There is nothing to send back."}), 400
    reason = ((request.get_json(silent=True) or {}).get("reason") or "").strip()
    if not reason:
        return jsonify({"message": "Please give a reason so the employee knows what to fix."}), 400
    flow_documents.update_one({"_id": rec["_id"]}, {"$set": {"status": "rejected", "reject_reason": reason[:500]}})
    _notify("employee", rec["employee_id"], "notification", "Please upload this document again",
            f"{rec.get('title') or 'Document'}: {reason[:200]}", {"type": "documents"})
    return jsonify({"message": "Sent back to the employee."}), 200


@app.post("/api/hr/flow-documents/<doc_id>/remind")
@require_hr
def hr_flow_doc_remind(doc_id):
    rec = _find_flow_doc(doc_id)
    if not rec:
        return jsonify({"message": "Document not found."}), 404
    _notify("employee", rec["employee_id"], "reminder", f"Reminder: {rec.get('title') or 'a document'}",
            "HR is waiting for this. Open the Documents tab.", {"type": "documents"})
    return jsonify({"message": "Reminder sent."}), 200


@app.post("/api/hr/flow-surveys/<survey_id>/remind")
@require_hr
def hr_flow_survey_remind(survey_id):
    rec = _find_flow_survey(survey_id)
    if not rec:
        return jsonify({"message": "Survey not found."}), 404
    _notify("employee", rec["employee_id"], "reminder", f"Reminder: {rec.get('title') or 'a survey'}",
            "HR is waiting for your answers. Open the Documents tab.", {"type": "documents"})
    return jsonify({"message": "Reminder sent."}), 200


# ---------- Finishing: the End step, completion, and closing the login ----------
#
# Every onboarding / offboarding flow ends with a locked End step. It turns
# green by itself once EVERY step above it is done (HR's own steps, documents
# and surveys included) AND the employee's checklist is complete. At that
# moment the process is marked completed with a date (status.completed /
# status.completed_at), the people involved are told, and it moves out of the
# "in progress" lists into "Completed".
#
# Offboarding also closes the employee's SELMS login: never before the last
# working day (they still work that day), but from the day after it - or as
# soon as the offboarding is completed on or after the last working day.


def _login_closed(doc):
    st = doc.get("offboarding_status") or {}
    if not st.get("started"):
        return False
    try:
        last_day = datetime.strptime(st.get("last_working_day") or "", "%Y-%m-%d").date()
    except ValueError:
        return False
    today = _today_my()
    return today > last_day or (bool(st.get("completed")) and today >= last_day)


def _login_status_text(doc):
    st = doc.get("offboarding_status") or {}
    last_day = st.get("last_working_day")
    if _login_closed(doc):
        return f"Closed (last working day {last_day})"
    return f"Open until the end of {last_day}" if last_day else "Open"


def _first_open_flow_step(doc, process):
    run = _onboarding_run(doc) if process == "onboarding" else _offboarding_run(doc)
    end = END_ONBOARDING if process == "onboarding" else END_OFFBOARDING
    return next((s["label"] for s in run if s["state"] == "current" and s["label"] != end), None)


def _complete_process(emp, process):
    """Marks the process completed (once) and tells the people involved."""
    eid, name = emp["employee_id"], emp.get("full_name", "the employee")
    key = f"{process}_status"
    now = datetime.now(timezone.utc).isoformat()
    result = users.update_one({"employee_id": eid, f"{key}.completed": {"$ne": True}},
                              {"$set": {f"{key}.completed": True, f"{key}.completed_at": now}})
    if not result.modified_count:
        return False
    if process == "onboarding":
        _notify("hr", None, "notification", f"Onboarding complete: {name}",
                "Every step is done.", {"type": "lifecycle"})
        _notify("employee", eid, "notification", "Your onboarding is complete",
                "Everything is done. Welcome to the team!", {"type": "onboarding"})
    else:
        last_day = (emp.get("offboarding_status") or {}).get("last_working_day") or "their last working day"
        text = f"Their SELMS login closes after {last_day}."
        _notify("hr", None, "notification", f"Offboarding complete: {name}", text, {"type": "lifecycle"})
        _notify("it", None, "notification", f"Offboarding complete: {name}", text, {"type": "requests"})
        _notify("employee", eid, "notification", "Your offboarding is complete",
                f"Your SELMS login stays open until the end of {last_day}, then it closes.", {"type": "offboarding"})
    return True


def _check_completion(employee_id, process):
    """If every step above End is done and the checklist is complete, finish
    the process. Safe to call any time."""
    emp = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not emp:
        return False
    st = emp.get(f"{process}_status") or {}
    if not st.get("started") or st.get("completed"):
        return False
    if process == "onboarding":
        nodes, done, end = _flow_step_nodes(employee_id), _flow_step_done, END_ONBOARDING
        _items, progress = _onboarding_checklist(emp)
    else:
        nodes, done, end = _offboarding_step_nodes(employee_id), _offboarding_step_done, END_OFFBOARDING
        _items, progress = _offboarding_checklist(emp)
    if progress < 100 or not all(done(emp, n) for n in nodes if n.get("label") != end):
        return False
    return _complete_process(emp, process)


def _sweep_lifecycle():
    """Runs on a timer (and from 'run checks'): finishes anything whose last
    step was done without going through an endpoint that checks (for example
    the employee adding their photo), and closes logins whose date has come."""
    for emp in users.find({"role": "employee", "onboarding_status.started": True,
                           "onboarding_status.completed": {"$ne": True}}):
        _advance_safely(emp["employee_id"])
    for emp in users.find({"role": "employee", "offboarding_status.started": True,
                           "offboarding_status.completed": {"$ne": True}}):
        _advance_offboarding_safely(emp["employee_id"])
    _due_email_reminders()
    _equipment_return_reminders()
    for emp in users.find({"role": "employee", "offboarding_status.started": True,
                           "offboarding_status.login_closed_at": {"$exists": False}}):
        if _login_closed(emp):
            users.update_one({"employee_id": emp["employee_id"]}, {"$set": {
                "offboarding_status.login_closed_at": datetime.now(timezone.utc).isoformat()}})
            name = emp.get("full_name", "the employee")
            for role in ("hr", "it"):
                _notify(role, None, "notification", f"Login closed: {name}",
                        "Their SELMS login was switched off after their last working day.",
                        {"type": "lifecycle"} if role == "hr" else {"type": "requests"})


# ---------- Timing on steps ----------
#
# A step can carry a "when" (node["when"] = {mode, days, date}) - only the
# steps where timing matters most:
#   "do"       SELMS performs it, so it waits for its date: tell IT (Prepare
#              laptop / Retrieve IT equipment), hand out Documents, send a Survey.
#   "meeting"  the session is still booked straight away, but aimed at that day
#              (orientation, exit interview).
#   "reminder" HR sends it (welcome / offboarding email); HR is reminded when
#              the date arrives and the step isn't shown as "waiting for you"
#              before then.
# Two timings only: now (the default) or on_date, which carries a date and a
# time ("HH:MM", Malaysia time; older steps saved without one mean midnight).
# A date can be set per employee (the Timing window shows their hire date to
# help choose it). The timer checks every REMINDER_INTERVAL_MINUTES, so a step
# timed for 09:00 runs within that many minutes of 09:00.

TIMED_ONBOARDING = {"Send welcome email": "reminder", "Prepare IT equipment": "do", "Schedule orientation": "meeting"}
TIMED_OFFBOARDING = {"Send offboarding email": "reminder", "Retrieve IT equipment": "do",
                     "Schedule exit interview": "meeting"}


def _timing_kind(node, process):
    if node.get("step") in EMPLOYEE_STEP_TYPES or node.get("step") in ("notification", "email"):
        return "do"
    kind = (TIMED_ONBOARDING if process == "onboarding" else TIMED_OFFBOARDING).get(node.get("label"))
    if kind:
        return kind
    # HR's own steps added with "+" (email, notification, meeting...): HR does
    # them, so a timing means "remind me on this day".
    if node.get("type") == "action" and not node.get("locked"):
        return "reminder"
    return None


def _as_date(value):
    try:
        return datetime.strptime(str(value)[:10], "%Y-%m-%d").date()
    except (ValueError, TypeError):
        return None


def _step_target_at(emp, node, process):
    """The moment (Malaysia time) this step is timed for, or None (= do it
    now). Only two timings exist: immediately, or on a specific date + time."""
    when = node.get("when") or {}
    if when.get("mode") != "on_date" or not _timing_kind(node, process):
        return None
    day = _as_date(when.get("date"))
    if day is None:
        return None
    match = re.fullmatch(r"(\d{1,2}):(\d{2})", str(when.get("time") or ""))
    hour, minute = (int(match.group(1)), int(match.group(2))) if match else (0, 0)
    if hour > 23 or minute > 59:
        hour, minute = 0, 0
    if process == "offboarding" and emp:
        # Everything in offboarding happens by the last working day: the
        # employee's login closes the day after, so later would be too late.
        last_day = _as_date((emp.get("offboarding_status") or {}).get("last_working_day"))
        if last_day and day > last_day:
            day = last_day
    return datetime(day.year, day.month, day.day, hour, minute, tzinfo=MY_TZ)


def _step_target_date(emp, node, process):
    """Just the day of _step_target_at, or None."""
    target = _step_target_at(emp, node, process)
    return target.date() if target else None


def _step_is_due(emp, node, process):
    target = _step_target_at(emp, node, process)
    return target is None or datetime.now(MY_TZ) >= target


def _at_text(target):
    """21 Oct 2026, 9:00 AM - the time is left out for older steps saved without one."""
    text = target.strftime("%d %b %Y")
    if target.hour or target.minute:
        text += ", " + target.strftime("%I:%M %p").lstrip("0")
    return text


def _when_text(node, process):
    target = _step_target_at(None, node, process)
    return f"for {_at_text(target)}" if target else "as soon as it starts"


def _timed_hint(emp, node, process, base):
    kind = _timing_kind(node, process)
    target = _step_target_at(emp, node, process)
    if not kind or target is None:
        return base
    text = _at_text(target)
    if kind == "meeting":
        return f"Aimed at {text}. {base}"
    if datetime.now(MY_TZ) < target:
        return f"Scheduled for {text}. {base}"
    return base


def _timing_fields(emp, node, process, state):
    """Extra keys for a step in the run list."""
    kind = _timing_kind(node, process)
    target = _step_target_at(emp, node, process)
    booked = None
    if kind == "meeting" and emp:
        b = bookings.find_one({"employee_id": emp["employee_id"],
                               "session_type": "orientation" if process == "onboarding" else "exit_interview"},
                              sort=[("date", 1), ("start_time", 1)])
        if b:
            booked = f"Booked for {_clock_text(b['date'], b['start_time'])}"
            if b.get("aimed_note"):
                booked += f" ({b['aimed_note']})"
    return {
        "booked": booked,
        "due_on": target.date().isoformat() if target else None,
        "due_at": target.isoformat() if target else None,
        # true while a step is scheduled for later, so it isn't asked of anyone yet
        "waiting": bool(state == "current" and kind in ("do", "reminder") and target
                        and datetime.now(MY_TZ) < target),
    }


def _due_email_reminders():
    """HR is told once when a timed step that HR does by hand comes due (the
    welcome / offboarding email, or any step they added with "+")."""
    for process in ("onboarding", "offboarding"):
        for emp in users.find({"role": "employee", f"{process}_status.started": True,
                               f"{process}_status.completed": {"$ne": True}}):
            eid = emp["employee_id"]
            nodes = _flow_step_nodes(eid) if process == "onboarding" else _offboarding_step_nodes(eid)
            for node in nodes:
                if _timing_kind(node, process) != "reminder" or _step_target_date(emp, node, process) is None:
                    continue
                done = _flow_step_done(emp, node) if process == "onboarding" else _offboarding_step_done(emp, node)
                if done or not _step_is_due(emp, node, process):
                    continue
                label = node.get("label")
                if label in ("Send welcome email", "Send offboarding email") \
                        and (emp.get(f"{process}_status") or {}).get("email_saved"):
                    continue  # saved: SELMS sends it, HR doesn't need reminding
                title = {"Send welcome email": "Time to send the welcome email",
                         "Send offboarding email": "Time to send the offboarding email"}.get(label, f"Time for: {label}")
                _notify("hr", None, "reminder", f"{title}: {emp.get('full_name')}",
                        f"It was timed {_when_text(node, process)}.", {"type": "lifecycle"},
                        dedupe_key=f"due:{process}:{eid}:{node.get('id')}")


# ---------- The "Send notification" step ----------
#
# node["step"] == "notification", node["notify"] = {title, message,
#   to: {employee, it, hr}, people: [{id, name, role}]}.
# SELMS sends it by itself when the step is reached and its date (if any) has
# come - bell notifications only - and marks the step done. HR / IT accounts
# share one inbox per role, so picking an HR or IT person reaches that inbox.


class _KeepUnknown(dict):
    def __missing__(self, key):
        return "{" + key + "}"


def _render_notification_text(text, emp):
    hire = _as_date(emp.get("hire_date"))
    values = _KeepUnknown(
        name=emp.get("full_name") or "", department=emp.get("department") or "",
        job_title=emp.get("job_title") or "", employee_id=emp.get("employee_id") or "",
        hire_date=hire.strftime("%d %b %Y") if hire else "",
    )
    try:
        return (text or "").format_map(values)
    except (ValueError, IndexError, KeyError):
        return text or ""


def _notification_recipients_text(cfg):
    to = cfg.get("to") or {}
    parts = [label for key, label in (("employee", "the employee"), ("it", "IT"), ("hr", "HR")) if to.get(key)]
    parts += [p.get("name") or "someone" for p in cfg.get("people") or []]
    return ", ".join(parts) or "no one yet"


def _send_notification_step(emp, node, process):
    cfg = node.get("notify") or {}
    to = cfg.get("to") or {}
    eid = emp["employee_id"]
    title = _render_notification_text(cfg.get("title") or "Notification", emp)
    body = _render_notification_text(cfg.get("message") or "", emp)
    staff_done = set()

    def staff(role):
        if role in staff_done:
            return
        staff_done.add(role)
        _notify(role, None, "notification", title, body,
                {"type": "requests"} if role == "it" else {"type": "lifecycle"})

    if to.get("employee"):
        _notify("employee", eid, "notification", title, body, {"type": process})
    if to.get("it"):
        staff("it")
    if to.get("hr"):
        staff("hr")
    for person in cfg.get("people") or []:
        found = _find_person(person.get("id"))
        if not found:
            continue
        if found.get("role") == "employee":
            if found["employee_id"] == eid and to.get("employee"):
                continue
            _notify("employee", found["employee_id"], "notification", title, body, {})
        else:
            staff(found.get("role"))
    users.update_one({"employee_id": eid}, {"$set": {
        f"{process}_status.notification_steps.{node['id']}": datetime.now(timezone.utc).isoformat()}})


# ---------- Email steps: Save, then the flow sends ----------
#
# Emails in a flow are SAVED, not sent by hand. Saving stores the subject and
# body on the employee; the flow sends it when the step comes due (straight
# away, or on the date set in its timing). The same goes for HR's own
# "Send email" step (step == "email"), whose subject / body / recipients live
# on the node: node["email"] = {subject, message, to: {employee, it, hr}}.
# Recipients are only ever the employee in the flow, the IT team or the HR team.


def _public_base_url():
    if PUBLIC_BASE_URL:
        return PUBLIC_BASE_URL
    try:
        return request.host_url.rstrip("/")
    except RuntimeError:  # no request (the timer)
        return "http://localhost:5000"


def _send_welcome_email(emp, subject, body_text, by_email, advance=True):
    """Sends the saved welcome email now. Returns (ok, message)."""
    employee_id = emp["employee_id"]
    to_email = emp.get("personal_email") or emp.get("work_email")
    if not to_email:
        return False, "This employee has no email address."
    token = secrets.token_urlsafe(24)
    confirm_url = f"{_public_base_url()}/api/onboarding/confirm/{token}"
    try:
        orientation = bookings.find_one({"employee_id": employee_id, "session_type": "orientation"},
                                        sort=[("date", 1), ("start_time", 1)])
        send_email(to_email=to_email, subject=subject,
                   html_body=_welcome_email_html(body_text, confirm_url, _orientation_email_block(orientation),
                                                 "" if "Your SELMS sign-in" in body_text
                                                 else _credentials_email_block(emp)))
    except Exception as exc:  # noqa: BLE001
        return False, f"Could not send email: {exc}"
    _require_password_reset(employee_id)
    now = datetime.now(timezone.utc).isoformat()
    existing = emp.get("onboarding_status") or {}
    users.update_one({"employee_id": employee_id}, {"$set": {
        "onboarding_status.started": True,
        "onboarding_status.started_at": existing.get("started_at") or now,
        "onboarding_status.started_by": existing.get("started_by") or by_email,
        "onboarding_status.welcome_email_sent": True,
        "onboarding_status.welcome_email_sent_at": now,
        "onboarding_status.email_subject": subject,
        "onboarding_status.email_body": body_text,
        "onboarding_status.confirm_token": token,
        "onboarding_status.email_confirmed": False,
        "onboarding_status.email_confirmed_at": None,
    }})
    if advance:
        _advance_safely(employee_id)
    return True, f"Email sent to {to_email}."


def _send_offboarding_email(emp, subject, body_text, advance=True):
    employee_id = emp["employee_id"]
    to_email = emp.get("personal_email") or emp.get("work_email")
    if not to_email:
        return False, "This employee has no email address."
    try:
        send_email(to_email=to_email, subject=subject, html_body=_offboarding_email_html(emp, body_text))
    except Exception as exc:  # noqa: BLE001
        return False, f"Could not send email: {exc}"
    now = datetime.now(timezone.utc).isoformat()
    users.update_one({"employee_id": employee_id}, {"$set": {
        "offboarding_status.offboarding_email_sent": True,
        "offboarding_status.offboarding_email_sent_at": now,
        "offboarding_status.email_subject": subject,
        "offboarding_status.email_body": body_text,
    }})
    if advance:
        _advance_offboarding_safely(employee_id)
    return True, f"Email sent to {to_email}."


def _save_email(employee_id, process):
    """Shared by the two save-email routes. Stores the reviewed email, then lets
    the flow send it if its step is due."""
    emp = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not emp:
        return jsonify({"message": "Employee not found."}), 404
    status_key = f"{process}_status"
    st = emp.get(status_key) or {}
    sent_flag = "welcome_email_sent" if process == "onboarding" else "offboarding_email_sent"
    if st.get(sent_flag):
        return jsonify({"message": "This email was already sent."}), 400
    body = request.get_json(silent=True) or {}
    subject = (body.get("subject") or "").strip()
    body_text = (body.get("body") or "").strip()
    if not subject or not body_text:
        return jsonify({"message": "Subject and body are required."}), 400
    users.update_one({"employee_id": employee_id}, {"$set": {
        f"{status_key}.email_subject": subject, f"{status_key}.email_body": body_text,
        f"{status_key}.email_saved": True}})
    if not st.get("started"):
        return jsonify({"message": f"Saved. SELMS sends it when {process} starts.", "sent": False}), 200

    label = "Send welcome email" if process == "onboarding" else "Send offboarding email"
    nodes = _flow_step_nodes(employee_id) if process == "onboarding" else _offboarding_step_nodes(employee_id)
    node = next((n for n in nodes if n.get("label") == label), None)
    (_advance_onboarding if process == "onboarding" else _advance_offboarding)(employee_id)
    fresh = users.find_one({"employee_id": employee_id}) or emp
    if (fresh.get(status_key) or {}).get(sent_flag):
        to = fresh.get("personal_email") or fresh.get("work_email")
        return jsonify({"message": f"Saved and sent to {to}.", "sent": True}), 200
    target = _step_target_at(fresh, node, process) if node else None
    if target:
        return jsonify({"message": f"Saved. SELMS sends it on {_at_text(target)}.", "sent": False}), 200
    return jsonify({"message": "Saved, but it could not be sent yet. SELMS will try again.", "sent": False}), 200


@app.post("/api/onboarding/<employee_id>/save-email")
@require_hr
def onboarding_save_email(employee_id):
    return _save_email(employee_id, "onboarding")


@app.post("/api/offboarding/<employee_id>/save-email")
@require_hr
def offboarding_save_email(employee_id):
    return _save_email(employee_id, "offboarding")


def _email_recipients(emp, cfg):
    """Addresses for a custom email step: the employee in the flow, the IT team,
    the HR team - nobody else."""
    to = cfg.get("to") or {}
    found = []
    if to.get("employee"):
        found.append(emp.get("personal_email") or emp.get("work_email") or emp.get("email"))
    if to.get("it"):
        found += [u.get("email") for u in users.find({"role": "it"})]
    if to.get("hr"):
        found += [u.get("email") for u in users.find({"role": "hr"})]
    seen, out = set(), []
    for address in found:
        if address and address.lower() not in seen:
            seen.add(address.lower())
            out.append(address)
    return out


def _email_step_recipients_text(cfg):
    to = cfg.get("to") or {}
    parts = [label for key, label in (("employee", "the employee"), ("it", "IT"), ("hr", "HR")) if to.get(key)]
    return ", ".join(parts) or "no one yet"


def _send_email_step(emp, node, process):
    """Sends HR's own email step. Safe to call again: addresses already sent to
    are skipped, so a failure half-way never double-sends."""
    cfg = node.get("email") or {}
    eid = emp["employee_id"]
    subject = _render_notification_text(cfg.get("subject") or "(no subject)", emp)
    text = _render_notification_text(cfg.get("message") or "", emp)
    key = f"{process}_status.email_steps.{node['id']}"
    done = ((emp.get(f"{process}_status") or {}).get("email_steps") or {}).get(node["id"]) or {}
    already = set(done.get("sent") or [])
    for address in _email_recipients(emp, cfg):
        if address in already:
            continue
        try:
            send_email(to_email=address, subject=subject, html_body=_plain_email_html(text))
        except Exception as exc:  # noqa: BLE001
            users.update_one({"employee_id": eid}, {"$set": {f"{key}.error": str(exc)[:200]}})
            _notify("hr", None, "alert", f"Email could not be sent: {subject}",
                    f"For {emp.get('full_name')}: {str(exc)[:160]}. SELMS will try again.", {"type": "lifecycle"},
                    dedupe_key=f"emailfail:{process}:{eid}:{node['id']}")
            return False
        users.update_one({"employee_id": eid}, {"$addToSet": {f"{key}.sent": address}})
        already.add(address)
    users.update_one({"employee_id": eid}, {"$set": {f"{key}.done_at": datetime.now(timezone.utc).isoformat()},
                                            "$unset": {f"{key}.error": ""}})
    return True


# ---------- Documents and surveys as lines on the employee's own checklist ----------

def _flow_checklist_items(employee_id, process, include_documents=False):
    items = []
    if include_documents:
        given = list(flow_documents.find({"employee_id": employee_id, "process": process}))
        if given:
            items.append({"id": "flow_documents", "label": "Documents from HR",
                          "done": all(_flow_doc_complete(d) for d in given), "done_at": None})
    for sv in flow_surveys.find({"employee_id": employee_id, "process": process}).sort("created_at", 1):
        items.append({"id": f"survey:{sv['_id']}", "label": sv.get("title") or "Survey",
                      "done": sv.get("status") == "submitted", "done_at": sv.get("submitted_at")})
    return items


# --- Google Calendar / Meet ---
#
# One-way: SELMS owns the schedule (the Smart Schedule grid and its conflict
# checks); for online sessions it also asks Google to create a
# matching calendar event purely to get a Meet link and send invites.
# Nothing is read back from Google. HR connects their Google account once
# (OAuth); only the refresh token is stored, in the `settings` collection.
# Uses plain HTTPS calls (urllib, like the Anthropic call above) - no
# extra Google client libraries needed.

GOOGLE_SCOPE = "https://www.googleapis.com/auth/calendar.events"
MEETING_MODES = ("in_person", "online")


def _google_configured():
    return bool(GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET)


def _google_connected():
    return bool(settings.find_one({"_id": "google"}))


def _google_request(method, url, *, json_body=None, form=None, token=None):
    """Returns (status_code, parsed_json_or_None). Never raises on an HTTP
    error status - callers decide what a 4xx means."""
    headers = {}
    data = None
    if json_body is not None:
        data = _json.dumps(json_body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    elif form is not None:
        data = urllib.parse.urlencode(form).encode("utf-8")
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=15) as res:
            raw = res.read()
            return res.status, (_json.loads(raw) if raw else None)
    except urllib.error.HTTPError as exc:
        raw = exc.read()
        try:
            return exc.code, _json.loads(raw)
        except Exception:  # noqa: BLE001
            return exc.code, {"error": raw.decode("utf-8", "replace")[:300]}


def _google_access_token():
    """Trades the stored refresh token for a short-lived access token."""
    record = settings.find_one({"_id": "google"})
    if not record:
        raise RuntimeError("Google isn't connected yet.")
    status, data = _google_request("POST", "https://oauth2.googleapis.com/token", form={
        "client_id": GOOGLE_CLIENT_ID,
        "client_secret": GOOGLE_CLIENT_SECRET,
        "refresh_token": record["refresh_token"],
        "grant_type": "refresh_token",
    })
    if status != 200 or not data or "access_token" not in data:
        # Typically "invalid_grant": the login expired (Testing-mode apps
        # expire after ~7 days) or access was revoked. Reconnecting fixes it.
        raise RuntimeError("Google login expired - please reconnect Google.")
    return data["access_token"]


@app.get("/api/google/status")
@require_hr_or_it
def google_status():
    return jsonify({"configured": _google_configured(), "connected": _google_connected(),
                    "default_meeting_url": bool(DEFAULT_MEETING_URL)}), 200


@app.get("/api/google/auth-url")
@require_hr
def google_auth_url():
    """The Flutter app opens this URL in a browser tab. The state value ties
    the callback back to a login HR actually started."""
    if not _google_configured():
        return jsonify({"message": "GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET aren't set in .env."}), 400
    state = secrets.token_urlsafe(24)
    settings.update_one({"_id": "google_oauth_state"}, {"$set": {
        "state": state, "created_at": datetime.now(timezone.utc).isoformat(),
    }}, upsert=True)
    query = urllib.parse.urlencode({
        "client_id": GOOGLE_CLIENT_ID,
        "redirect_uri": GOOGLE_REDIRECT_URI,
        "response_type": "code",
        "scope": GOOGLE_SCOPE,
        "access_type": "offline",   # needed to receive a refresh token
        "prompt": "consent",        # ...and to receive it every time
        "state": state,
    })
    return jsonify({"url": f"https://accounts.google.com/o/oauth2/v2/auth?{query}"}), 200


@app.get("/api/google/callback")
def google_callback():
    """Google redirects the browser here after HR clicks Allow. Public (no
    HR token - it's a plain browser redirect), so it only accepts a code
    that arrives with the one-time state issued by google_auth_url."""
    def page(message, status=200):
        return f"<div style='font-family:sans-serif;padding:40px'><h3>{message}</h3></div>", status

    if request.args.get("error"):
        return page(f"Google sign-in was cancelled ({request.args['error']}). You can close this tab.", 400)

    pending = settings.find_one({"_id": "google_oauth_state"})
    state = request.args.get("state")
    code = request.args.get("code")
    if not pending or not state or not secrets.compare_digest(pending["state"], state) or not code:
        return page("This sign-in link is invalid or has expired. Start again from SELMS.", 400)
    created = _parse_iso(pending.get("created_at"))
    if not created or datetime.now(timezone.utc) - created > timedelta(minutes=15):
        return page("This sign-in link has expired. Start again from SELMS.", 400)
    settings.delete_one({"_id": "google_oauth_state"})

    status, data = _google_request("POST", "https://oauth2.googleapis.com/token", form={
        "code": code,
        "client_id": GOOGLE_CLIENT_ID,
        "client_secret": GOOGLE_CLIENT_SECRET,
        "redirect_uri": GOOGLE_REDIRECT_URI,
        "grant_type": "authorization_code",
    })
    if status != 200 or not data or not data.get("refresh_token"):
        return page("Google didn't return a login. Please try connecting again.", 502)

    settings.update_one({"_id": "google"}, {"$set": {
        "refresh_token": data["refresh_token"],
        "connected_at": datetime.now(timezone.utc).isoformat(),
    }}, upsert=True)
    return page("Google connected to SELMS. You can close this tab and go back to the app.")


@app.post("/api/google/disconnect")
@require_hr
def google_disconnect():
    settings.delete_one({"_id": "google"})
    return jsonify({"message": "Google disconnected."}), 200


def _meeting_attendee_emails(employee_id, session_type, attendees=None):
    """Who gets the calendar invite. The new hire goes to their PERSONAL
    email first - their work email may not be usable until day one. IT staff
    are added for the sessions IT takes part in."""
    emails = []
    if employee_id:
        emp = users.find_one({"employee_id": employee_id, "role": "employee"})
        if emp:
            emails.append(emp.get("personal_email") or emp.get("work_email"))
    if session_type in ("orientation", "it_handoff"):
        emails.extend(u.get("email") for u in users.find({"role": "it"}))
    emails.extend(a.get("email") for a in (attendees or []))
    seen, out = set(), []
    for e in emails:
        if e and e.lower() not in seen:
            seen.add(e.lower())
            out.append(e)
    return out


def _create_google_meet_event(title, description, date, start_time, duration_minutes, attendees):
    """Creates the calendar event and returns (meet_url, event_id)."""
    start = datetime.strptime(f"{date} {start_time}", "%Y-%m-%d %H:%M")
    end = start + timedelta(minutes=int(duration_minutes))
    event = {
        "summary": title,
        "description": description,
        "start": {"dateTime": start.strftime("%Y-%m-%dT%H:%M:00"), "timeZone": SCHEDULE_TIMEZONE},
        "end": {"dateTime": end.strftime("%Y-%m-%dT%H:%M:00"), "timeZone": SCHEDULE_TIMEZONE},
        "attendees": [{"email": e} for e in attendees],
        "conferenceData": {"createRequest": {
            "requestId": uuid.uuid4().hex,
            "conferenceSolutionKey": {"type": "hangoutsMeet"},
        }},
    }
    status, data = _google_request(
        "POST",
        "https://www.googleapis.com/calendar/v3/calendars/primary/events"
        "?conferenceDataVersion=1&sendUpdates=all",
        json_body=event, token=_google_access_token(),
    )
    if status not in (200, 201) or not data:
        reason = (data or {}).get("error")
        if isinstance(reason, dict):
            reason = reason.get("message")
        raise RuntimeError(f"Google Calendar refused the event ({status}): {reason}")

    meet_url = data.get("hangoutLink")
    if not meet_url:
        for entry in (data.get("conferenceData") or {}).get("entryPoints", []):
            if entry.get("entryPointType") == "video":
                meet_url = entry.get("uri")
    if not meet_url:
        raise RuntimeError("Google created the event but returned no Meet link.")
    return meet_url, data["id"]


def _delete_google_event(event_id):
    """Best-effort: a missing/already-deleted event is fine."""
    if not event_id or not _google_connected():
        return
    try:
        _google_request(
            "DELETE",
            f"https://www.googleapis.com/calendar/v3/calendars/primary/events/{event_id}?sendUpdates=all",
            token=_google_access_token(),
        )
    except Exception as exc:  # noqa: BLE001
        print(f"[Google] could not delete event {event_id}: {exc}")


def _provision_meeting(booking):
    """Works out the meeting link for a new booking dict (before insert).
    Returns (fields_to_merge_into_the_booking, warning_or_None). In-person
    sessions get nothing; a link HR typed in by hand is kept as-is;
    otherwise a Google Meet is created if Google is connected, falling back
    to DEFAULT_MEETING_URL. A failure never blocks the booking - the session
    is still scheduled and the warning tells HR the link is missing."""
    if booking.get("mode", "in_person") == "in_person" or booking.get("meeting_url"):
        return {}, None

    warning = None
    if _google_connected():
        try:
            employee_name = booking.get("employee_name") or ""
            title = booking["title"] + (f" - {employee_name}" if employee_name else "")
            meet_url, event_id = _create_google_meet_event(
                title, f"{booking['title']} scheduled via SELMS.",
                booking["date"], booking["start_time"], booking["duration_minutes"],
                _meeting_attendee_emails(booking.get("employee_id"), booking["session_type"],
                                         booking.get("attendees")),
            )
            return {"meeting_url": meet_url, "google_event_id": event_id, "meeting_source": "google"}, None
        except Exception as exc:  # noqa: BLE001
            warning = f"Google Meet link could not be created: {exc}"
    elif _google_configured():
        warning = "Google isn't connected yet, so no Meet link was created."

    if DEFAULT_MEETING_URL:
        return {"meeting_url": DEFAULT_MEETING_URL, "meeting_source": "default"}, warning
    return {}, warning or "No meeting link yet - add one by hand or connect Google."


def _delete_booking_docs(query):
    """Deletes bookings matching the query, removing their Google events
    first so the invites disappear too. Returns the number deleted."""
    count = 0
    for b in list(bookings.find(query)):
        _delete_google_event(b.get("google_event_id"))
        bookings.delete_one({"_id": b["_id"]})
        count += 1
    return count


# --- Smart Schedule (bookings) ---
#
# HR and IT share this calendar (IT sees the same bookings and can add IT
# handoffs / other sessions); connecting Google stays HR-only. A booking is
# a single session on the calendar: an onboarding
# orientation, an IT handoff, an offboarding exit interview, or a manually
# added session. "Smart" scheduling means checking existing bookings
# before suggesting a slot — not a real external calendar integration,
# just conflict-checking against what SELMS itself already knows about.

WORKDAY_START_MINUTES = 10 * 60  # 10:00 AM
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


def _person_ref(doc):
    """{id, name, role, email, department, profile_image_url} for anyone who
    can be invited to a session. Employees are identified by employee id,
    HR / IT staff by their account id."""
    role = doc.get("role")
    if role == "employee":
        return {"id": doc["employee_id"], "name": doc.get("full_name"), "role": "employee",
                # new hires may not use their work mailbox yet - same rule as orientation invites
                "email": doc.get("personal_email") or doc.get("work_email") or doc.get("email"),
                "department": doc.get("department"), "profile_image_url": doc.get("profile_image_url")}
    return {"id": str(doc["_id"]), "name": doc.get("full_name") or doc.get("email"), "role": role,
            "email": doc.get("email"), "department": "HR" if role == "hr" else "IT", "profile_image_url": None}


def _find_person(person_id):
    doc = users.find_one({"employee_id": person_id, "role": "employee"})
    if doc:
        return doc
    try:
        return users.find_one({"_id": ObjectId(person_id), "role": {"$in": ["hr", "it"]}})
    except Exception:  # noqa: BLE001
        return None


@app.get("/api/people/lookup")
@require_hr_or_it
def lookup_people():
    """Everyone a session can include - employees plus HR and IT staff -
    for the 'Who's attending' picker when scheduling."""
    q = (request.args.get("q") or "").strip()
    query = {"role": {"$in": ["employee", "hr", "it"]}}
    if q:
        pattern = re.escape(q)
        query["$or"] = [{"full_name": {"$regex": pattern, "$options": "i"}},
                         {"employee_id": {"$regex": pattern, "$options": "i"}},
                         {"email": {"$regex": pattern, "$options": "i"}}]
    docs = list(users.find(query).sort("full_name", 1).limit(60))
    return jsonify({"people": [_person_ref(d) for d in docs]}), 200


def _booking_overlaps(a_start, a_end, b_start, b_end):
    return a_start < b_end and b_start < a_end


def _clashing_booking(date, start_min, duration_minutes):
    """The existing session that overlaps this time on this day, or None."""
    for b in bookings.find({"date": date}):
        b_start = _time_to_minutes(b["start_time"])
        b_end = b_start + int(b.get("duration_minutes") or DEFAULT_SESSION_MINUTES)
        if _booking_overlaps(start_min, start_min + int(duration_minutes), b_start, b_end):
            return b
    return None


def _time12(hhmm):
    """"14:30" -> 2:30 PM"""
    try:
        return datetime.strptime(hhmm, "%H:%M").strftime("%I:%M %p").lstrip("0")
    except (TypeError, ValueError):
        return str(hhmm)


def _clock_text(date, start_time):
    """"2026-10-24", "14:30" -> 24 Oct 2026, 2:30 PM"""
    day = _as_date(date)
    return f"{day.strftime('%d %b %Y') if day else date}, {_time12(start_time)}"


@app.post("/api/bookings")
@require_hr_or_it
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
    mode = body.get("mode") or "in_person"
    meeting_url = (body.get("meeting_url") or "").strip()

    if not date or not start_time:
        return jsonify({"message": "date and start_time are required."}), 400
    if session_type not in SESSION_TYPES:
        return jsonify({"message": "Unrecognised session_type."}), 400
    if mode not in MEETING_MODES:
        return jsonify({"message": "Unrecognised mode."}), 400
    if not title:
        return jsonify({"message": "Give the session a name."}), 400
    try:
        start_min = _time_to_minutes(start_time)
    except (ValueError, AttributeError):
        return jsonify({"message": "Invalid start time."}), 400
    if start_min < WORKDAY_START_MINUTES or start_min + int(duration_minutes) > WORKDAY_END_MINUTES:
        return jsonify({"message": "Sessions must be between 10:00 AM and 5:00 PM."}), 400
    clash = _clashing_booking(date, start_min, duration_minutes)
    if clash:
        c_start = _time_to_minutes(clash["start_time"])
        c_end = c_start + int(clash.get("duration_minutes") or DEFAULT_SESSION_MINUTES)
        who = f" - {clash['employee_name']}" if clash.get("employee_name") else ""
        span = f"{_time12(clash['start_time'])} - {_time12(_minutes_to_time(c_end))}"
        return jsonify({"message": f"That time clashes with {clash.get('title') or 'another session'}{who} "
                                   f"({span}). Pick another time."}), 409

    # Who's attending: any number of employees / HR / IT staff, resolved on
    # the server so names and emails are always the real ones.
    attendees, seen_ids = [], set()
    wanted = [a.get("id") if isinstance(a, dict) else a for a in (body.get("attendees") or [])]
    if employee_id:
        wanted.insert(0, employee_id)
    for pid in wanted:
        if not pid or pid in seen_ids:
            continue
        person = _find_person(str(pid))
        if person:
            seen_ids.add(pid)
            attendees.append(_person_ref(person))
    # The first employee attending is the session's "employee" (what the
    # onboarding/offboarding flows and the calendar label look at).
    if not employee_id:
        first = next((a for a in attendees if a["role"] == "employee"), None)
        if first:
            employee_id, employee_name = first["id"], first["name"]

    doc = {
        "employee_id": employee_id,
        "employee_name": employee_name,
        "session_type": session_type,
        "title": title,
        "date": date,
        "start_time": start_time,
        "duration_minutes": duration_minutes,
        "location": location,
        "mode": mode,
        "meeting_url": meeting_url,
        "attendees": attendees,
        "created_by": g.current_user.get("email"),
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    extra, warning = _provision_meeting(doc)
    doc.update(extra)
    result = bookings.insert_one(doc)
    _email_booking(doc)
    if g.current_user.get("role") == "it":
        _notify("hr", None, "notification", f"IT booked a session: {title}",
                f"{_clock_text(date, start_time)}" + (f" with {employee_name}." if employee_name else "."),
                {"type": "schedule"})
    doc["_id"] = str(result.inserted_id)
    doc["meeting_warning"] = warning  # response only - not stored
    # A hand-booked exit interview satisfies that step of the offboarding flow.
    if session_type == "exit_interview" and employee_id:
        _advance_offboarding_safely(employee_id)
    return jsonify(doc), 201


@app.patch("/api/bookings/<booking_id>")
@require_hr_or_it
def update_booking(booking_id):
    """Lets HR fix a session's link/location after the fact - e.g. paste a
    Teams link, or add one when Google wasn't connected at booking time."""
    try:
        oid = ObjectId(booking_id)
    except Exception:  # noqa: BLE001
        return jsonify({"message": "Invalid booking id."}), 400
    body = request.get_json(silent=True) or {}
    updates = {}
    if "meeting_url" in body:
        updates["meeting_url"] = (body.get("meeting_url") or "").strip()
        updates["meeting_source"] = "manual" if updates["meeting_url"] else None
    if "location" in body:
        updates["location"] = (body.get("location") or "").strip()
    if "mode" in body:
        if body["mode"] not in MEETING_MODES:
            return jsonify({"message": "Unrecognised mode."}), 400
        updates["mode"] = body["mode"]
    if not updates:
        return jsonify({"message": "Nothing to update."}), 400
    result = bookings.update_one({"_id": oid}, {"$set": updates})
    if result.matched_count == 0:
        return jsonify({"message": "Booking not found."}), 404
    return jsonify({"message": "Updated."}), 200


@app.delete("/api/bookings/<booking_id>")
@require_hr_or_it
def delete_booking(booking_id):
    """Cancels one session. Also removes its Google event (so the invite
    disappears), and if it was an employee's orientation with no other
    orientation left, un-ticks the 'Orientation Session' onboarding step."""
    try:
        oid = ObjectId(booking_id)
    except Exception:  # noqa: BLE001
        return jsonify({"message": "Invalid booking id."}), 400
    booking = bookings.find_one({"_id": oid})
    if not booking:
        return jsonify({"message": "Booking not found."}), 404

    _delete_booking_docs({"_id": oid})

    employee_id = booking.get("employee_id")
    if (booking.get("session_type") == "orientation" and employee_id
            and not bookings.find_one({"employee_id": employee_id, "session_type": "orientation"})):
        users.update_one({"employee_id": employee_id}, {"$set": {
            "onboarding_status.orientation_scheduled": False,
            "onboarding_status.orientation_scheduled_at": None,
        }})
    # Same for an exit interview: un-tick it so the flow shows it as pending.
    if (booking.get("session_type") == "exit_interview" and employee_id
            and not bookings.find_one({"employee_id": employee_id, "session_type": "exit_interview"})):
        users.update_one({"employee_id": employee_id, "offboarding_status.started": True}, {"$set": {
            "offboarding_status.exit_interview_scheduled": False,
            "offboarding_status.exit_interview_scheduled_at": None,
        }})
    return jsonify({"message": "Session cancelled."}), 200


@app.get("/api/bookings")
@require_hr_or_it
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


SHIPMENT_STATUS_TEXT = {"pending": "being prepared", "order_created": "booked with Pos", "dropped_off": "on its way",
                        "delivered": "delivered", "cancelled": "cancelled"}


@app.get("/api/schedule/it-tasks")
@require_hr_or_it
def list_it_tasks():
    """?start=YYYY-MM-DD&end=YYYY-MM-DD - IT's own row on the Smart Schedule:
    equipment to assign to new hires (due by the "Prepare IT equipment"
    timing, else their hire date), equipment to retrieve from leavers (due
    by the "Retrieve IT equipment" timing, else their last working day) and
    Pos Malaysia parcels both ways (on the day of their latest update)."""
    start, end = _as_date(request.args.get("start")), _as_date(request.args.get("end"))
    if not start or not end:
        return jsonify({"message": "start and end are required (YYYY-MM-DD)."}), 400
    items = []

    def add(at_date, at_time, label, emp, process, kind, done, hint):
        if at_date and start <= at_date <= end:
            items.append({"date": at_date.isoformat(), "time": at_time, "label": label, "kind": kind,
                          "process": process, "employee_id": emp["employee_id"],
                          "employee_name": emp.get("full_name") or emp["employee_id"], "done": bool(done),
                          "timing": "on_date", "hint": hint})

    for process, step_label in (("onboarding", "Prepare IT equipment"), ("offboarding", "Retrieve IT equipment")):
        for emp in users.find({"role": "employee", f"{process}_status.started": True,
                               f"{process}_status.completed": {"$ne": True}}):
            eid = emp["employee_id"]
            nodes = _flow_step_nodes(eid) if process == "onboarding" else _offboarding_step_nodes(eid)
            node = next((n for n in nodes if n.get("label") == step_label), None)
            target = _step_target_at(emp, node, process) if node else None
            st = emp.get(f"{process}_status") or {}
            if process == "onboarding":
                fallback = _as_date(emp.get("hire_date"))
                needed = [str(n) for n in (emp.get("equipment_needed") or []) if str(n).strip()]
                if not needed:
                    continue
                add(target.date() if target else fallback,
                    target.strftime("%H:%M") if target and (target.hour or target.minute) else None,
                    f"Assign equipment ({', '.join(needed)})", emp, process, "assign",
                    _equipment_fulfilment(emp)[2], "Assign the requested items in Products before their first day.")
            else:
                fallback = _as_date(st.get("last_working_day"))
                left = equipment.count_documents({"assigned_to_employee_id": eid, "status": "assigned"})
                total = left + sum(1 for i in _return_items(emp) if i["returned"])
                if not total:
                    continue
                add(target.date() if target else fallback,
                    target.strftime("%H:%M") if target and (target.hour or target.minute) else None,
                    f"Retrieve equipment ({total - left} of {total} back)", emp, process, "retrieve",
                    left == 0, "Collect the items back (Products or Scan) by their last working day.")

    for parcel in shipments.find({"status": {"$ne": "cancelled"}}):
        emp = users.find_one({"employee_id": parcel.get("employee_id"), "role": "employee"})
        if not emp:
            continue
        status = parcel.get("status") or "pending"
        stamp = next((parcel.get(k) for k in ("delivered_at", "dropped_off_at", "order_created_at", "created_at")
                      if parcel.get(k)), None)
        at = _parse_iso(stamp) if isinstance(stamp, str) else None
        if not at:
            continue
        at = at.astimezone(MY_TZ)
        outgoing = parcel.get("direction") != "return"
        add(at.date(), at.strftime("%H:%M"),
            f"{'Parcel to employee' if outgoing else 'Return parcel'} - {SHIPMENT_STATUS_TEXT.get(status, status)}",
            emp, "onboarding" if outgoing else "offboarding", "shipment", status == "delivered",
            f"Pos Malaysia {parcel.get('pos_reference') or '(no reference yet)'} - open Shipments.")
    items.sort(key=lambda i: (i["date"], i["time"] or "", i["employee_name"]))
    return jsonify({"tasks": items}), 200


def _step_happened_at(emp, node, process):
    """When SELMS actually did this step (sent the email / notification, gave
    out the documents or survey, told IT), or None if it hasn't yet."""
    st = emp.get(f"{process}_status") or {}
    step, label = node.get("step"), node.get("label")
    if step == "email":
        value = ((st.get("email_steps") or {}).get(node.get("id")) or {}).get("done_at")
    elif step == "notification":
        value = (st.get("notification_steps") or {}).get(node.get("id"))
    elif step in EMPLOYEE_STEP_TYPES:
        coll = flow_documents if step == "documents" else flow_surveys
        rec = coll.find_one({"employee_id": emp["employee_id"], "process": process, "step_id": node.get("id")},
                            sort=[("created_at", 1)])
        value = rec.get("created_at") if rec else None
    elif label == "Send welcome email":
        value = st.get("welcome_email_sent_at")
    elif label == "Send offboarding email":
        value = st.get("offboarding_email_sent_at")
    elif label in ("Prepare IT equipment", "Retrieve IT equipment"):
        value = st.get("it_notified_at")
    else:
        value = None
    return _parse_iso(value) if isinstance(value, str) else None


@app.get("/api/schedule/sends")
@require_hr
def list_scheduled_sends():
    """?start=YYYY-MM-DD&end=YYYY-MM-DD - what the onboarding / offboarding
    flows send in that range (emails, notifications, documents, surveys,
    telling IT, HR reminders), so the Smart Schedule can show them beside the
    meetings. A step timed "On a specific date" shows at that time; an
    "Immediately" step shows when SELMS did it (or, still waiting, on the day
    the process started). Meetings are left out: they are already bookings."""
    start, end = _as_date(request.args.get("start")), _as_date(request.args.get("end"))
    if not start or not end:
        return jsonify({"message": "start and end are required (YYYY-MM-DD)."}), 400
    items = []
    for process in ("onboarding", "offboarding"):
        for emp in users.find({"role": "employee", f"{process}_status.started": True}):
            eid = emp["employee_id"]
            st = emp.get(f"{process}_status") or {}
            if process == "onboarding":
                nodes, done = _flow_step_nodes(eid), _flow_step_done
            else:
                nodes, done = _offboarding_step_nodes(eid), _offboarding_step_done
            for node in nodes:
                kind = _timing_kind(node, process)
                if kind not in ("do", "reminder"):
                    continue
                if node.get("step") == "documents" and not node.get("docs"):
                    continue  # no documents added: nothing is sent
                target = _step_target_at(emp, node, process)
                at = target or _step_happened_at(emp, node, process) or _parse_iso(st.get("started_at"))
                if at is None:
                    continue
                at = at.astimezone(MY_TZ)
                if not start <= at.date() <= end:
                    continue
                label = node.get("label") or ""
                # A saved welcome / offboarding email is sent by SELMS, not just a reminder.
                if label in ("Send welcome email", "Send offboarding email") and st.get("email_saved"):
                    kind = "do"
                items.append({
                    "date": at.date().isoformat(),
                    # older dated steps saved without a time mean "start of that day"
                    "time": None if target and not (at.hour or at.minute) else at.strftime("%H:%M"),
                    "timing": "on_date" if target else "now",
                    "label": label, "kind": kind, "process": process,
                    "employee_id": eid, "employee_name": emp.get("full_name") or eid,
                    "done": bool(done(emp, node)),
                })
    items.sort(key=lambda i: (i["date"], i["time"] or "", i["employee_name"]))
    return jsonify({"sends": items}), 200


def _find_next_available_slot(duration_minutes, not_after=None, not_before=None):
    """Looks 14 days ahead from today, finds the first work-hours slot of
    the requested duration that doesn't overlap any existing booking.
    Simple linear scan — fine at this scale, not meant to be a production
    optimizer. Returns {date, start_time, duration_minutes} or None.
    Shared by the manual GET /api/bookings/suggest route and the
    automated onboarding/offboarding flows, so "smart scheduling" means
    the same thing everywhere.

    Works in Malaysia time (the working day the slots refer to) and never
    returns a time that has already passed today. not_after ("YYYY-MM-DD")
    caps the search, e.g. an exit interview has to happen by the last
    working day."""
    now_my = datetime.now(MY_TZ)
    today = now_my.date()
    now_minutes = now_my.hour * 60 + now_my.minute
    cap = not_after if (isinstance(not_after, str) and re.fullmatch(r"\d{4}-\d{2}-\d{2}", not_after)) else None
    # not_before ("YYYY-MM-DD", a date, or a datetime whose time is the earliest
    # start on that day): start looking from there (never in the past)
    first_day = today
    earliest_minutes = 0
    if isinstance(not_before, datetime):
        at = not_before.astimezone(MY_TZ)
        earliest, earliest_minutes = at.date(), at.hour * 60 + at.minute
    else:
        earliest = _as_date(not_before) if not_before else None
    if earliest and earliest > today:
        first_day = earliest
    for day_offset in range(14):
        day = first_day + timedelta(days=day_offset)
        if day.weekday() >= 5:  # skip Sat/Sun
            continue
        date_str = day.isoformat()
        if cap and date_str > cap:
            break
        day_bookings = list(bookings.find({"date": date_str}))
        busy = []
        for b in day_bookings:
            b_start = _time_to_minutes(b["start_time"])
            b_end = b_start + int(b.get("duration_minutes") or DEFAULT_SESSION_MINUTES)
            busy.append((b_start, b_end))

        slot_start = WORKDAY_START_MINUTES
        while slot_start + duration_minutes <= WORKDAY_END_MINUTES:
            slot_end = slot_start + duration_minutes
            already_past = (day == today and slot_start <= now_minutes) or \
                (day == earliest and slot_start < earliest_minutes)
            if not already_past and not any(_booking_overlaps(slot_start, slot_end, b[0], b[1]) for b in busy):
                return {
                    "date": date_str,
                    "start_time": _minutes_to_time(slot_start),
                    "duration_minutes": duration_minutes,
                }
            slot_start += 30  # step forward in 30-minute increments

    return None


@app.get("/api/bookings/suggest")
@require_hr_or_it
def suggest_booking_slot():
    """?duration_minutes=30[&not_after=YYYY-MM-DD] - not_after keeps it on or
    before a day, e.g. an exit interview by the last working day."""
    not_after = request.args.get("not_after") or None
    slot = _find_next_available_slot(int(request.args.get("duration_minutes") or DEFAULT_SESSION_MINUTES),
                                     not_after=not_after)
    if slot is None:
        if not_after and _as_date(not_after):
            return jsonify({"message": f"No free slot on or before {_as_date(not_after).strftime('%d %b %Y')} "
                                       f"(their last working day) - free up a slot in Smart Schedule."}), 404
        return jsonify({"message": "No free slot found in the next 14 days."}), 404
    return jsonify(slot), 200


# ---------- Shipments (Pos Malaysia e-Connote) ----------
#
# IT sends equipment to remote hires ("to_employee") and gets it
# back from leavers ("return"). SELMS can't create the Pos order itself -
# e-Connote is a self-service website with no public API - so IT creates
# it there and records the outcome here: the Pos reference number and a
# screenshot of the QR Pos gives back (kept as an image, not re-drawn,
# because the format Pos encodes isn't documented). SELMS supplies what IT
# would otherwise retype (recipient name, phone, address, items) and
# tracks the status from "pending" through to "delivered".

POS_ECONNOTE_URL = "https://send.pos.com.my/home/e-connote?lg=en"
POS_TRACKING_URL = "https://tracking.pos.com.my/tracking"  # Pos's own tracker; SELMS can't query it
# Where returned equipment is sent. Fill these in .env.
COMPANY_NAME = os.environ.get("COMPANY_NAME", "")
COMPANY_ADDRESS = os.environ.get("COMPANY_ADDRESS", "")
COMPANY_PHONE = os.environ.get("COMPANY_PHONE", "")

SHIPMENT_DIRECTIONS = ("to_employee", "return")
SHIPMENT_STATUSES = ("pending", "order_created", "dropped_off", "delivered", "cancelled")
SHIPMENT_STATUS_STAMPS = {
    "order_created": "order_created_at",
    "dropped_off": "dropped_off_at",
    "delivered": "delivered_at",
}
SHIPPING_WORK_LOCATIONS = ("Remote",)


def _shipment_items(employee_doc, direction):
    """What goes in the parcel: the equipment currently assigned to the
    employee; for an outgoing parcel with nothing assigned yet, fall back
    to what they asked for at registration."""
    assigned = list(equipment.find({
        "assigned_to_employee_id": employee_doc["employee_id"], "status": "assigned",
    }))
    if assigned:
        return [_asset_card(e) for e in assigned]
    if direction == "to_employee":
        return [{"name": n, "type": None, "asset_tag": ""} for n in (employee_doc.get("equipment_needed") or [])]
    return []


def _parcel_items(doc):
    """What the card shows as in the parcel, read live: the equipment
    assigned to the employee right now (so items assigned after the parcel
    was created appear, with their photo and ID); once nothing is assigned
    any more (a return that has come back), the items saved on the parcel,
    with their photo looked up again."""
    assigned = list(equipment.find({"assigned_to_employee_id": doc["employee_id"], "status": "assigned"}))
    if assigned:
        return [_asset_card(e) for e in assigned]
    out = []
    for it in doc.get("items") or []:
        found = None
        try:
            if it.get("equipment_id"):
                found = equipment.find_one({"_id": ObjectId(it["equipment_id"])})
        except Exception:  # noqa: BLE001
            found = None
        if found is None and it.get("asset_tag"):
            found = equipment.find_one({"asset_tag": it["asset_tag"]})
        out.append(_asset_card(found) if found else {**it, "photo_url": None, "serial_number": ""})
    return out


def _shipment_public(doc):
    """The shipment plus everything IT needs on the card, read live from
    the employee record so an address fix is picked up immediately."""
    out = {**doc, "_id": str(doc["_id"])}
    out["items"] = _parcel_items(doc)
    emp = users.find_one({"employee_id": doc["employee_id"]}) or {}
    out["recipient"] = {
        "name": emp.get("full_name") or doc.get("employee_name"),
        "phone": emp.get("mobile_number") or "",
        "address_line": emp.get("address_line") or "",
        "postcode": emp.get("postcode") or "",
        "state": emp.get("state") or "",
        "email": emp.get("personal_email") or "",
        "work_location_type": emp.get("work_location_type"),
        "profile_image_url": emp.get("profile_image_url"),
    }
    out["company"] = {"name": COMPANY_NAME, "address": COMPANY_ADDRESS, "phone": COMPANY_PHONE}
    out["pos_url"] = POS_ECONNOTE_URL
    out["tracking_url"] = POS_TRACKING_URL
    return out


@app.get("/api/shipments")
@require_hr_or_it
def list_shipments():
    query = {}
    direction = request.args.get("direction")
    if direction in SHIPMENT_DIRECTIONS:
        query["direction"] = direction
    docs = list(shipments.find(query).sort("created_at", -1))
    # Active ones first; finished/cancelled sink to the bottom.
    docs.sort(key=lambda d: d["status"] in ("delivered", "cancelled"))
    return jsonify({"shipments": [_shipment_public(d) for d in docs]}), 200


@app.get("/api/shipments/eligible")
@require_hr_or_it
def shipment_eligible_employees():
    """Remote employees IT can start a shipment for, with the
    context that helps pick the right one (onboarding/offboarding status,
    equipment already assigned, whether a parcel is already in progress)."""
    direction = request.args.get("direction", "to_employee")
    out = []
    for d in users.find({"role": "employee", "work_location_type": {"$in": list(SHIPPING_WORK_LOCATIONS)}}):
        active = shipments.find_one({
            "employee_id": d["employee_id"], "direction": direction,
            "status": {"$nin": ["delivered", "cancelled"]},
        })
        out.append({
            "employee_id": d["employee_id"],
            "full_name": d["full_name"],
            "department": d.get("department"),
            "work_location_type": d.get("work_location_type"),
            "profile_image_url": d.get("profile_image_url"),
            "onboarding_started": bool((d.get("onboarding_status") or {}).get("started")),
            "offboarding_started": bool((d.get("offboarding_status") or {}).get("started")),
            "assigned_count": equipment.count_documents({
                "assigned_to_employee_id": d["employee_id"], "status": "assigned"}),
            "has_active_shipment": bool(active),
            # Everything IT needs to fill in the Pos form BEFORE the
            # shipment exists in SELMS.
            "recipient": {
                "name": d.get("full_name"),
                "phone": d.get("mobile_number") or "",
                "address_line": d.get("address_line") or "",
                "postcode": d.get("postcode") or "",
                "state": d.get("state") or "",
            },
            "items": _shipment_items(d, direction),
        })
    # People in the matching process first (onboarding for outgoing,
    # offboarding for returns), then alphabetical.
    flag = "onboarding_started" if direction == "to_employee" else "offboarding_started"
    out.sort(key=lambda e: (not e[flag], e["full_name"].lower()))
    return jsonify({
        "employees": out,
        "company": {"name": COMPANY_NAME, "address": COMPANY_ADDRESS, "phone": COMPANY_PHONE},
        "pos_url": POS_ECONNOTE_URL,
    }), 200


@app.post("/api/shipments")
@require_hr_or_it
def create_shipment():
    body = request.get_json(silent=True) or {}
    employee_id = (body.get("employee_id") or "").strip()
    direction = body.get("direction") or "to_employee"
    if direction not in SHIPMENT_DIRECTIONS:
        return jsonify({"message": "Unrecognised direction."}), 400

    emp = users.find_one({"employee_id": employee_id, "role": "employee"})
    if not emp:
        return jsonify({"message": "Employee not found."}), 404
    if shipments.find_one({"employee_id": employee_id, "direction": direction,
                           "status": {"$nin": ["delivered", "cancelled"]}}):
        return jsonify({"message": "There is already an open shipment of this kind for this employee."}), 409

    now = datetime.now(timezone.utc).isoformat()
    doc = {
        "employee_id": employee_id,
        "employee_name": emp["full_name"],
        "direction": direction,
        "status": "pending",
        "items": _shipment_items(emp, direction),
        "pos_reference": "",
        "qr_image_url": None,
        "notes": (body.get("notes") or "").strip(),
        "created_by": g.current_user["email"],
        "created_at": now,
    }
    result = shipments.insert_one(doc)
    doc["_id"] = result.inserted_id
    _advance_safely(employee_id)
    return jsonify(_shipment_public(doc)), 201


def _get_shipment_or_404(shipment_id):
    try:
        oid = ObjectId(shipment_id)
    except Exception:  # noqa: BLE001
        return None
    return shipments.find_one({"_id": oid})


@app.patch("/api/shipments/<shipment_id>")
@require_hr_or_it
def update_shipment(shipment_id):
    doc = _get_shipment_or_404(shipment_id)
    if not doc:
        return jsonify({"message": "Shipment not found."}), 404

    body = request.get_json(silent=True) or {}
    updates = {}
    if "pos_reference" in body:
        updates["pos_reference"] = (body.get("pos_reference") or "").strip()
    if "notes" in body:
        updates["notes"] = (body.get("notes") or "").strip()
    if "status" in body:
        if body["status"] not in SHIPMENT_STATUSES:
            return jsonify({"message": "Unrecognised status."}), 400
        updates["status"] = body["status"]
        stamp = SHIPMENT_STATUS_STAMPS.get(body["status"])
        if stamp and not doc.get(stamp):
            updates[stamp] = datetime.now(timezone.utc).isoformat()
    if not updates:
        return jsonify({"message": "Nothing to update."}), 400

    # Having a reference number means the order exists on the Pos site -
    # move a still-pending shipment along without a separate click.
    if updates.get("pos_reference") and doc["status"] == "pending" and "status" not in updates:
        updates["status"] = "order_created"
        updates["order_created_at"] = datetime.now(timezone.utc).isoformat()

    shipments.update_one({"_id": doc["_id"]}, {"$set": updates})
    new_status = updates.get("status")
    if new_status in ("dropped_off", "delivered") and new_status != doc.get("status"):
        ref = updates.get("pos_reference") or doc.get("pos_reference") or ""
        name = doc.get("employee_name") or "an employee"
        if doc.get("direction") == "to_employee":
            title = f"Parcel {'posted' if new_status == 'dropped_off' else 'delivered'}: {name}"
        else:
            title = f"Return parcel {'on its way' if new_status == 'dropped_off' else 'received'}: {name}"
        _notify("hr", None, "notification", title, f"Pos Malaysia{f' {ref}' if ref else ''}.",
                {"type": "shipments"}, dedupe_key=f"hr-shipment:{doc['_id']}:{new_status}")
    if new_status in ("dropped_off", "delivered") and doc.get("direction") == "to_employee":
        ref = updates.get("pos_reference") or doc.get("pos_reference") or ""
        _notify("employee", doc["employee_id"], "notification",
                "Your equipment is on its way" if new_status == "dropped_off" else "Your equipment was delivered",
                ("Posted via Pos Malaysia" + (f" - reference {ref}." if ref else ".")) if new_status == "dropped_off"
                else "Your equipment has been delivered.",
                {"type": "onboarding"}, dedupe_key=f"shipment:{doc['_id']}:{new_status}")
    _advance_safely(doc["employee_id"])
    return jsonify(_shipment_public(shipments.find_one({"_id": doc["_id"]}))), 200


@app.post("/api/shipments/<shipment_id>/reject")
@require_hr_or_it
def reject_return_shipment(shipment_id):
    """IT cancelling a leaver's return parcel because the details aren't
    right (wrong tracking number, unreadable QR, ...). The parcel is closed
    off, the employee is told why and asked to send it again - their
    tracking number and QR are cleared so they can redo them."""
    doc = _get_shipment_or_404(shipment_id)
    if not doc:
        return jsonify({"message": "Shipment not found."}), 404
    if doc.get("direction") != "return":
        return jsonify({"message": "Only return parcels can be sent back to the employee."}), 400
    if doc.get("status") in ("delivered", "cancelled"):
        return jsonify({"message": "This parcel is already closed."}), 400
    reason = ((request.get_json(silent=True) or {}).get("reason") or "").strip()[:300]
    now = datetime.now(timezone.utc).isoformat()
    shipments.update_one({"_id": doc["_id"]}, {"$set": {
        "status": "cancelled", "cancelled_at": now, "cancel_reason": reason}})
    users.update_one({"employee_id": doc["employee_id"]}, {
        "$set": {"offboarding_status.return_rejected": {"reason": reason, "at": now}},
        "$unset": {"offboarding_status.posted_at": "", "offboarding_status.return_qr_url": ""}})
    ref = doc.get("pos_reference") or ""
    _notify("employee", doc["employee_id"], "notification", "Please send your return parcel details again",
            f"IT couldn't accept your return parcel{f' ({ref})' if ref else ''}"
            + (f": {reason}." if reason else ".")
            + " Please check it and send the tracking number and QR code again.",
            {"type": "offboarding"})
    return jsonify(_shipment_public(shipments.find_one({"_id": doc["_id"]}))), 200


@app.post("/api/shipments/<shipment_id>/qr")
@require_hr_or_it
def upload_shipment_qr(shipment_id):
    """Saves the screenshot of the QR code Pos Malaysia generated."""
    doc = _get_shipment_or_404(shipment_id)
    if not doc:
        return jsonify({"message": "Shipment not found."}), 404

    file = request.files.get("qr")
    if file is None or file.filename == "":
        return jsonify({"message": "No image was sent."}), 400
    ext = file.filename.rsplit(".", 1)[-1].lower() if "." in file.filename else ""
    if ext not in ALLOWED_PHOTO_EXTENSIONS:
        return jsonify({"message": "The QR image must be a JPG or PNG file."}), 400

    filename = secure_filename(f"shipment-{shipment_id}-qr.{ext}")
    file.save(os.path.join(UPLOAD_FOLDER, filename))
    url = f"/uploads/{filename}"
    shipments.update_one({"_id": doc["_id"]}, {"$set": {"qr_image_url": url}})
    return jsonify({"qr_image_url": url}), 200


@app.delete("/api/shipments/<shipment_id>")
@require_hr_or_it
def delete_shipment(shipment_id):
    doc = _get_shipment_or_404(shipment_id)
    if not doc:
        return jsonify({"message": "Shipment not found."}), 404
    shipments.delete_one({"_id": doc["_id"]})
    return jsonify({"message": "Shipment deleted."}), 200


# ---------- Notifications, reminders and alerts ----------
#
# One stored feed shared by every role:
#   notification - "FYI, something happened"
#   reminder     - "please do your part"   (employee, IT, HR)
#   alert        - "something is stuck"    (HR and IT only, never the employee)
#
# Staff (HR/IT) read it through the bell in the top bar; employees get the
# same items merged into their Alerts tab. Reminder wording is written by the
# AI from real facts only, and falls back to a plain sentence if the AI is
# unavailable. Rules run on a background timer (and on demand from HR), with
# at most ONE reminder per person per day so nobody is spammed.

notifications = db["notifications"]

MY_TZ = timezone(timedelta(hours=8))  # Malaysia has no daylight saving
REMINDER_INTERVAL_MINUTES = int(os.environ.get("REMINDER_INTERVAL_MINUTES", "10"))


def _today_my():
    return datetime.now(MY_TZ).date()


def _notify(recipient_role, recipient_id, kind, title, body, link=None, dedupe_key=None):
    """Stores one item. recipient_id is the employee id for employees and
    None for HR/IT (those are shared inboxes per role). A repeated
    dedupe_key for the same recipient is ignored. Never raises - a
    notification problem must not break the action that caused it."""
    try:
        if dedupe_key and notifications.find_one({
            "recipient_role": recipient_role, "recipient_id": recipient_id, "dedupe_key": dedupe_key,
        }):
            return None
        doc = {
            "recipient_role": recipient_role,
            "recipient_id": recipient_id,
            "kind": kind,
            "title": title,
            "body": body,
            "link": link or {},
            "dedupe_key": dedupe_key,
            "read_by": [],
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
        return notifications.insert_one(doc).inserted_id
    except Exception as exc:  # noqa: BLE001
        print(f"[notify] could not store notification: {exc}")
        return None


def _ai_reminder_text(facts, fallback):
    """One or two friendly sentences from the facts only; the fallback
    sentence is used when there's no key or the call fails."""
    if not ANTHROPIC_API_KEY:
        return fallback
    system = (
        "You write one short in-app message for an HR system called SELMS. "
        "At most two short sentences, friendly and professional. Use ONLY the "
        "facts provided - never invent names, dates or numbers. Do not start with "
        "a greeting such as Hi or Hello, no signature, no emojis."
    )
    try:
        text = _chat_completion(system, [{"role": "user", "content": facts}]).strip()
        return text or fallback
    except Exception as exc:  # noqa: BLE001
        print(f"[reminder] AI wording failed, using fallback: {exc}")
        return fallback


def _reminded_today(recipient_role, recipient_id):
    start_local = datetime.combine(_today_my(), datetime.min.time(), MY_TZ)
    return bool(notifications.find_one({
        "recipient_role": recipient_role, "recipient_id": recipient_id, "kind": "reminder",
        "created_at": {"$gte": start_local.astimezone(timezone.utc).isoformat()},
    }))


def run_reminder_checks():
    """Looks for things that need a nudge and stores them. Returns counts."""
    counts = {"reminders": 0, "alerts": 0}
    try:
        _sweep_lifecycle()
    except Exception as exc:  # noqa: BLE001
        print(f"[lifecycle sweep] failed: {exc}")
    now = datetime.now(timezone.utc)
    today = _today_my()
    tomorrow = (today + timedelta(days=1)).isoformat()

    # ---- employees: one reminder per person per day ----
    for emp in users.find({"role": "employee", "onboarding_status.started": True}):
        eid = emp["employee_id"]
        status = emp.get("onboarding_status") or {}
        _items, progress = _onboarding_checklist(emp)
        if progress >= 100:
            continue
        started = _parse_iso(status.get("started_at"))
        days = (now - started).days if started else 0
        name = emp.get("full_name", "the employee")
        candidates = []

        booking = bookings.find_one({"employee_id": eid, "session_type": "orientation", "date": tomorrow})
        if booking:
            when = booking.get("start_time", "")
            fmt = "online" if booking.get("mode") == "online" else "in person"
            candidates.append((
                "orientation_tomorrow", "Orientation tomorrow",
                f"Reminder for the employee (address them as 'you'). Their orientation is tomorrow at {when}, format: {fmt}.",
                f"Your orientation is tomorrow at {when} ({fmt}).",
            ))

        unsigned = [d["title"] for d in flow_documents.find({
            "employee_id": eid, "action": {"$in": ["acknowledge", "upload"]}, "status": {"$in": ["sent", "rejected"]}})]
        if unsigned and days >= 2:
            candidates.append((
                "documents_unsigned", "Documents waiting for you",
                f"Reminder for the employee (address them as 'you'). They still have to sign these documents: {', '.join(unsigned)}.",
                f"You still have {len(unsigned)} document(s) to sign: {', '.join(unsigned)}.",
            ))

        if status.get("welcome_email_sent") and not status.get("email_confirmed") and days >= 2:
            candidates.append((
                "email_unconfirmed", "Please confirm your welcome email",
                f"Reminder for the employee (address them as 'you'). They have not yet confirmed receiving the welcome email.",
                "Please confirm you received the welcome email using the button inside it.",
            ))

        if not emp.get("profile_image_url") and days >= 2:
            candidates.append((
                "photo_missing", "Add your profile photo",
                f"Reminder for the employee (address them as 'you'). They have not uploaded a profile photo yet.",
                "Please upload a profile photo on your Profile tab to finish your setup.",
            ))

        if candidates and not _reminded_today("employee", eid):
            key, title, facts, fallback = candidates[0]
            text = _ai_reminder_text(facts, fallback)
            if _notify("employee", eid, "reminder", title, text, {"type": "onboarding"},
                       dedupe_key=f"{key}:{eid}:{today}"):
                counts["reminders"] += 1

    # ---- IT: requests / returns not finished yet (once a day each) ----
    # Nothing to accept by hand: a request is done when the work is (see
    # _it_onboarding_tasks / _it_return_tasks). Until then IT is reminded,
    # daily from 3 days before the deadline (start date / last working day),
    # or once the request has waited 2 days.
    for kind, deadline_of, tasks_of, title in (
            ("equipment_request", lambda e, r: _as_date(e.get("hire_date")),
             lambda e, r: _it_onboarding_tasks(e), "Equipment still to prepare"),
            ("equipment_return_request",
             lambda e, r: _as_date((e.get("offboarding_status") or {}).get("last_working_day")),
             lambda e, r: _it_return_tasks(e, r), "Equipment still to collect")):
        for req in messages.find({"target_role": "it", "kind": kind, "request_status": "open"}):
            emp = users.find_one({"employee_id": req["employee_id"], "role": "employee"})
            if not emp:
                continue
            tasks, done = tasks_of(emp, req)
            if done:
                continue
            deadline = deadline_of(emp, req)
            days_left = (deadline - today).days if deadline else None
            created = _parse_iso(req.get("created_at"))
            waited = (now - created).days if created else 0
            if not ((days_left is not None and days_left <= 3) or waited >= 2):
                continue
            left = "; ".join(f"{t['label']} ({t['detail']})" for t in tasks if not t["done"])
            due = ("" if days_left is None else
                   f" Deadline {deadline.strftime('%d %b %Y')} ({'overdue' if days_left < 0 else 'today' if days_left == 0 else f'in {days_left} day(s)'}).")
            facts = (f"Reminder for the IT team about {emp['full_name']} "
                     f"({'new hire' if kind == 'equipment_request' else 'leaving the company'}). "
                     f"Still not done: {left}.{due}")
            fallback = f"{emp['full_name']}: {left}.{due}"
            if _notify("it", None, "reminder", f"{title}: {emp['full_name']}",
                       _ai_reminder_text(facts, fallback), {"type": "requests"},
                       dedupe_key=f"it_task:{kind}:{emp['employee_id']}:{today}"):
                counts["reminders"] += 1

    # ---- HR: anything delayed / at risk, and unsent welcome emails ----
    for rec in _lifecycle_records():
        if rec["status"] in ("delayed", "at_risk"):
            label = "Delayed" if rec["status"] == "delayed" else "At risk"
            if _notify("hr", None, "alert", f"{rec['full_name']} — {label} ({rec['process']})",
                       rec["status_reason"], {"type": "employee", "employee_id": rec["employee_id"]},
                       dedupe_key=f"lifecycle:{rec['employee_id']}:{rec['process']}:{rec['status']}:{today}"):
                counts["alerts"] += 1

    for emp in users.find({"role": "employee", "onboarding_status.started": True}):
        status = emp.get("onboarding_status") or {}
        started = _parse_iso(status.get("started_at"))
        if status.get("welcome_email_sent") or not started or (now - started).days < 1:
            continue
        if _notify("hr", None, "reminder", f"Welcome email still to send: {emp['full_name']}",
                   f"Onboarding started {(now - started).days} day(s) ago but the welcome email hasn't been sent.",
                   {"type": "employee", "employee_id": emp["employee_id"]},
                   dedupe_key=f"email_unsent:{emp['employee_id']}:{today}"):
            counts["reminders"] += 1

    return counts


def _reminder_loop():
    import time
    time.sleep(60)  # let the server finish starting
    while True:
        try:
            counts = run_reminder_checks()
            if counts["reminders"] or counts["alerts"]:
                print(f"[reminders] created {counts}")
        except Exception as exc:  # noqa: BLE001
            print(f"[reminders] check failed: {exc}")
        time.sleep(max(1, REMINDER_INTERVAL_MINUTES) * 60)


@app.post("/api/reminders/run")
@require_hr
def run_reminders_now():
    """Runs the checks immediately (the timer does this every few minutes) -
    handy for demos and testing."""
    return jsonify({"message": "Checks run.", **run_reminder_checks()}), 200


def _staff_view(doc, who):
    return {
        "id": str(doc["_id"]),
        "kind": doc["kind"],
        "title": doc["title"],
        "message": doc["body"],
        "link": doc.get("link") or {},
        "at": doc["created_at"],
        "read": who in (doc.get("read_by") or []),
    }


@app.get("/api/staff/notifications")
@require_hr_or_it
def staff_notifications():
    role, who = g.current_user.get("role"), g.current_user.get("email")
    docs = list(notifications.find({"recipient_role": role}).sort("created_at", -1).limit(40))
    unread = notifications.count_documents({"recipient_role": role, "read_by": {"$ne": who}})
    # Unread per link type, for the red counts on the sidebar tabs.
    by_type = {}
    # Unread employee messages (not bell items) - counted for the Messages tab.
    chats = sum(r["unread_count"] for r in _staff_inbox(
        "hr" if role == "hr" else "it", "hr_thread_read_by_hr_at" if role == "hr" else "it_thread_read_by_it_at"))
    if chats:
        by_type["chat"] = chats
    for row in notifications.aggregate([
            {"$match": {"recipient_role": role, "read_by": {"$ne": who}}},
            {"$group": {"_id": "$link.type", "n": {"$sum": 1}}}]):
        if row["_id"]:
            by_type[row["_id"]] = row["n"]
    return jsonify({"notifications": [_staff_view(d, who) for d in docs], "unread_count": unread,
                    "unread_by_type": by_type}), 200


@app.post("/api/staff/notifications/read-types")
@require_hr_or_it
def staff_notifications_read_types():
    """Opening a tab (e.g. IT's Messages) marks the notifications that point
    to it as read, so its red count clears - same as reading them in the bell."""
    types = [str(t) for t in ((request.get_json(silent=True) or {}).get("types") or [])][:10]
    if types:
        notifications.update_many(
            {"recipient_role": g.current_user.get("role"), "link.type": {"$in": types}},
            {"$addToSet": {"read_by": g.current_user.get("email")}},
        )
    return jsonify({"message": "Marked as read."}), 200


@app.post("/api/staff/notifications/<notification_id>/read")
@require_hr_or_it
def staff_notification_read(notification_id):
    try:
        oid = ObjectId(notification_id)
    except Exception:  # noqa: BLE001
        return jsonify({"message": "Invalid id."}), 400
    notifications.update_one(
        {"_id": oid, "recipient_role": g.current_user.get("role")},
        {"$addToSet": {"read_by": g.current_user.get("email")}},
    )
    return jsonify({"message": "Marked as read."}), 200


@app.post("/api/staff/notifications/read-all")
@require_hr_or_it
def staff_notifications_read_all():
    notifications.update_many(
        {"recipient_role": g.current_user.get("role")},
        {"$addToSet": {"read_by": g.current_user.get("email")}},
    )
    return jsonify({"message": "All marked as read."}), 200


# ---------- HR chatbot: employee lookups (tool calling) ----------
#
# The model never touches the database. It can ask for these three lookups;
# each one runs here, returns an explicit allow-list of fields, and HR is the
# only role that can reach it. NEVER included: IC/passport number, salary,
# password hash, the one-time Microsoft password.

_LOOKUP_FIELDS = (
    "employee_id", "full_name", "job_title", "department", "line_manager",
    "hire_date", "confirmation_date", "employment_status", "work_location_type",
    "work_email", "personal_email", "mobile_number",
    "gender", "nationality", "marital_status",
    "address_line", "postcode", "state",
    "emergency_contact_name", "emergency_contact_number", "emergency_contact_relationship",
    "remarks",
)


def _age_from(dob):
    parsed = _parse_iso(dob) if dob else None
    if not parsed:
        return None
    today = _today_my()
    return today.year - parsed.year - ((today.month, today.day) < (parsed.month, parsed.day))


def _lookup_view(emp):
    out = {k: emp.get(k) for k in _LOOKUP_FIELDS}
    out["date_of_birth"] = (emp.get("date_of_birth") or "")[:10] or None
    out["age"] = _age_from(emp.get("date_of_birth"))
    out["onboarding_started"] = bool((emp.get("onboarding_status") or {}).get("started"))
    out["offboarding_started"] = bool((emp.get("offboarding_status") or {}).get("started"))
    return out


HR_CHAT_TOOLS = [
    {
        "name": "find_employee",
        "description": "Find employees by employee ID (e.g. EMP-004) or by part of their name. "
                       "Returns their details. Use this for any question about a specific person.",
        "input_schema": {"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"]},
    },
    {
        "name": "get_progress",
        "description": "Where one employee is in onboarding (each step with its state and what it is "
                       "waiting on), their overall progress percent, equipment status, and offboarding "
                       "status. Takes an employee ID.",
        "input_schema": {"type": "object", "properties": {"employee_id": {"type": "string"}},
                         "required": ["employee_id"]},
    },
    {
        "name": "list_in_progress",
        "description": "Everyone currently being onboarded or offboarded, with their current step and status.",
        "input_schema": {"type": "object", "properties": {}},
    },
]


def _run_hr_tool(name, args):
    if name == "find_employee":
        q = (args.get("query") or "").strip()
        if not q:
            return {"error": "query is required"}
        pattern = re.escape(q)
        docs = list(users.find({"role": "employee", "$or": [
            {"employee_id": {"$regex": f"^{pattern}$", "$options": "i"}},
            {"full_name": {"$regex": pattern, "$options": "i"}},
        ]}).limit(5))
        return {"matches": [_lookup_view(d) for d in docs]} if docs else {"matches": [], "note": "No match."}

    if name == "get_progress":
        emp = users.find_one({"employee_id": (args.get("employee_id") or "").strip(), "role": "employee"})
        if not emp:
            return {"error": "Employee not found."}
        out = {"employee_id": emp["employee_id"], "full_name": emp["full_name"]}
        if (emp.get("onboarding_status") or {}).get("started"):
            _items, pct = _onboarding_checklist(emp)
            eq_items, _extra, ready, _at = _equipment_fulfilment(emp)
            out["onboarding"] = {
                "progress_percent": pct,
                "steps": [{"step": s["label"], "state": s["state"], "waiting_on": s["hint"]}
                          for s in _onboarding_run(emp)],
                "equipment": [{"item": i["type"], "assigned": i["assigned"]} for i in eq_items],
            }
        else:
            out["onboarding"] = "not started"
        off = emp.get("offboarding_status") or {}
        if off.get("started"):
            _items, pct = _offboarding_checklist(emp)
            out["offboarding"] = {"progress_percent": pct, "last_working_day": off.get("last_working_day"),
                                  "departure_type": off.get("departure_type")}
        else:
            out["offboarding"] = "not started"
        return out

    if name == "list_in_progress":
        return {"people": [
            {"employee_id": r["employee_id"], "name": r["full_name"], "process": r["process"],
             "progress_percent": r["progress_percent"], "current_step": r["current_step"], "status": r["status"]}
            for r in _lifecycle_records()
        ]}

    return {"error": f"Unknown tool {name}"}


def _chat_with_tools(system_prompt, messages, tools, run_tool, max_rounds=4):
    """Anthropic tool-use loop: let the model ask for lookups, run them,
    feed the results back, until it produces a final text answer."""
    if not ANTHROPIC_API_KEY:
        raise RuntimeError("ANTHROPIC_API_KEY is not configured on the server.")
    msgs = list(messages)
    for _ in range(max_rounds):
        req = urllib.request.Request(
            "https://api.anthropic.com/v1/messages",
            data=_json.dumps({
                "model": ANTHROPIC_MODEL, "max_tokens": 600,
                "system": system_prompt, "messages": msgs, "tools": tools,
            }).encode("utf-8"),
            headers={"Content-Type": "application/json", "x-api-key": ANTHROPIC_API_KEY,
                     "anthropic-version": "2023-06-01"},
        )
        with urllib.request.urlopen(req, timeout=30) as res:
            data = _json.loads(res.read())
        content = data.get("content", [])
        if data.get("stop_reason") != "tool_use":
            return "".join(b.get("text", "") for b in content if b.get("type") == "text").strip()
        msgs.append({"role": "assistant", "content": content})
        results = []
        for block in content:
            if block.get("type") == "tool_use":
                try:
                    out = run_tool(block["name"], block.get("input") or {})
                except Exception as exc:  # noqa: BLE001
                    out = {"error": str(exc)}
                results.append({"type": "tool_result", "tool_use_id": block["id"],
                                "content": _json.dumps(out, default=str)})
        msgs.append({"role": "user", "content": results})
    return "I couldn't finish that lookup - please try asking in a simpler way."


# ---------- Company documents (uploaded in the HR chat, shared by every chatbot) ----------
#
# HR attaches a file in the Admin Assistant; its text is extracted once and
# stored beside the file. All three chatbots (HR, IT, employee) get the same
# three lookup tools, so anyone can ask "where's the leave policy?" or
# "summarise the IT policy" and gets a Download button for what the bot used.
# Files live in uploads/documents under random names and are only served
# through the authenticated download route below (the public /uploads/<file>
# route can't reach that sub-folder).

documents = db["documents"]
DOCUMENTS_FOLDER = os.path.join(UPLOAD_FOLDER, "documents")
os.makedirs(DOCUMENTS_FOLDER, exist_ok=True)
ALLOWED_DOCUMENT_EXTENSIONS = {"pdf", "docx", "txt", "md"}
MAX_DOCUMENT_BYTES = 10 * 1024 * 1024
MAX_DOCUMENT_TEXT_CHARS = 300_000   # stored text cap per document
DOCUMENT_READ_CHARS = 12_000        # what one get_document call hands the model


def require_any_user(fn):
    """HR, IT or an employee's JWT - for things everyone may do, like
    downloading a shared company document."""
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
        if payload.get("role") not in ("hr", "it", "employee"):
            return jsonify({"message": "Not authorized."}), 403
        g.current_user = payload
        return fn(*args, **kwargs)
    return wrapper


def _extract_document_text(data: bytes, ext: str) -> str:
    """Plain text out of the uploaded file. Raises on a corrupt/encrypted
    file; returns '' for a scanned PDF (images only, nothing to read)."""
    if ext in ("txt", "md"):
        text = data.decode("utf-8", errors="replace")
    elif ext == "pdf":
        from pypdf import PdfReader
        reader = PdfReader(BytesIO(data))
        text = "\n\n".join((page.extract_text() or "") for page in reader.pages)
    else:  # docx
        import docx
        doc = docx.Document(BytesIO(data))
        parts = [p.text for p in doc.paragraphs]
        for table in doc.tables:
            for row in table.rows:
                parts.append(" | ".join(cell.text for cell in row.cells))
        text = "\n".join(parts)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text).strip()
    return text[:MAX_DOCUMENT_TEXT_CHARS]


def _document_public(doc):
    return {
        "id": str(doc["_id"]),
        "title": doc.get("title"),
        "original_name": doc.get("original_name"),
        "size": doc.get("size"),
        "uploaded_at": doc.get("uploaded_at"),
        "uploaded_by": doc.get("uploaded_by"),
        "summary": doc.get("summary") or "",
        "has_text": bool(doc.get("text")),
    }


def _summarise_document(title, text):
    """Best-effort 3-4 sentence summary shown right after upload (and kept so
    'what documents do we have' can describe each one cheaply). Never blocks
    the upload."""
    if not text or not ANTHROPIC_API_KEY:
        return ""
    try:
        return _chat_completion(
            "You summarise company documents for HR staff. Write 3 to 4 short sentences "
            "saying what the document is and its key points. Use only what the text says.",
            [{"role": "user", "content": f"Document title: {title}\n\n{text[:DOCUMENT_READ_CHARS]}"}],
        ).strip()
    except Exception as exc:  # noqa: BLE001
        print(f"[documents] summary failed for {title!r}: {exc}")
        return ""


@app.post("/api/hr/documents")
@require_hr
def upload_document():
    file = request.files.get("file")
    if file is None or not file.filename:
        return jsonify({"message": "No file was sent."}), 400
    original_name = secure_filename(file.filename) or "document"
    ext = original_name.rsplit(".", 1)[-1].lower() if "." in original_name else ""
    if ext not in ALLOWED_DOCUMENT_EXTENSIONS:
        return jsonify({"message": "Documents must be PDF, DOCX, TXT or MD files."}), 400
    data = file.read()
    if not data:
        return jsonify({"message": "That file is empty."}), 400
    if len(data) > MAX_DOCUMENT_BYTES:
        return jsonify({"message": "Documents can be up to 10 MB."}), 400

    try:
        text = _extract_document_text(data, ext)
    except Exception as exc:  # noqa: BLE001
        return jsonify({"message": f"Couldn't read that file ({exc}). Is it password-protected or damaged?"}), 400

    title = (request.form.get("title") or "").strip() or original_name.rsplit(".", 1)[0]
    stored_name = f"{uuid.uuid4().hex}.{ext}"
    with open(os.path.join(DOCUMENTS_FOLDER, stored_name), "wb") as fh:
        fh.write(data)

    summary = _summarise_document(title, text)
    doc = {
        "title": title,
        "original_name": original_name,
        "stored_name": stored_name,
        "size": len(data),
        "text": text,
        "summary": summary,
        "uploaded_by": g.current_user.get("email"),
        "uploaded_at": datetime.now(timezone.utc).isoformat(),
    }
    doc["_id"] = documents.insert_one(doc).inserted_id
    return jsonify({"document": _document_public(doc), "summary": summary}), 201


@app.get("/api/documents")
@require_any_user
def list_documents_route():
    docs = documents.find({}, {"text": 0}).sort("uploaded_at", -1)
    return jsonify({"documents": [_document_public(d) for d in docs]}), 200


@app.get("/api/documents/<document_id>/download")
@require_any_user
def download_document(document_id):
    try:
        doc = documents.find_one({"_id": ObjectId(document_id)})
    except Exception:  # noqa: BLE001
        doc = None
    if not doc:
        return jsonify({"message": "Document not found."}), 404
    return send_from_directory(DOCUMENTS_FOLDER, doc["stored_name"], as_attachment=True,
                               download_name=doc.get("original_name") or doc["stored_name"])


@app.delete("/api/hr/documents/<document_id>")
@require_hr
def delete_document(document_id):
    try:
        doc = documents.find_one({"_id": ObjectId(document_id)})
    except Exception:  # noqa: BLE001
        doc = None
    if not doc:
        return jsonify({"message": "Document not found."}), 404
    documents.delete_one({"_id": doc["_id"]})
    try:
        os.remove(os.path.join(DOCUMENTS_FOLDER, doc["stored_name"]))
    except OSError:
        pass
    return jsonify({"message": "Document deleted."}), 200


DOCUMENT_TOOLS = [
    {
        "name": "list_documents",
        "description": "List every company document HR has uploaded (title, upload date, who uploaded "
                       "it, short summary). Use for 'what documents do we have' or 'where is X'.",
        "input_schema": {"type": "object", "properties": {}},
    },
    {
        "name": "search_documents",
        "description": "Search the uploaded company documents by keywords (policy, form or template "
                       "names, or topics like 'annual leave'). Returns the best matches with a snippet.",
        "input_schema": {"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"]},
    },
    {
        "name": "get_document",
        "description": "Read the text of one document by its id (from list_documents or "
                       "search_documents). Long documents come in pieces: if next_offset is set, call "
                       "again with that offset to continue.",
        "input_schema": {"type": "object", "properties": {
            "document_id": {"type": "string"},
            "offset": {"type": "integer", "description": "Character offset to continue from (default 0)."},
        }, "required": ["document_id"]},
    },
]
_DOCUMENT_TOOL_NAMES = {t["name"] for t in DOCUMENT_TOOLS}

DOCUMENT_PROMPT = (
    "\n\nCompany documents: HR uploads policies, forms and templates, and you can look them up with "
    "list_documents, search_documents and get_document. Whenever someone asks about a policy, form, "
    "template or 'the document', use those tools instead of guessing. Answer or summarise only what "
    "the document actually says and name the document you used. If nothing matches, say no matching "
    "document has been uploaded. The app shows a Download button under your reply for every document "
    "you looked up, so just say it can be downloaded below - never write links."
)


def _snippet(text, tokens, radius=160):
    low = text.lower()
    hits = [low.find(t) for t in tokens if low.find(t) >= 0]
    if not hits:
        return text[:2 * radius].strip()
    start = max(0, min(hits) - radius)
    return ("…" if start else "") + text[start:start + 2 * radius].strip() + "…"


def _run_document_tool(name, args):
    """Result dict for a document tool call. A private '_refs' list names the
    documents involved so the route can attach Download buttons to the reply."""
    if name == "list_documents":
        rows = list(documents.find({}, {"text": 0}).sort("uploaded_at", -1).limit(30))
        return {
            "documents": [{"id": str(d["_id"]), "title": d.get("title"),
                           "uploaded_at": (d.get("uploaded_at") or "")[:10],
                           "uploaded_by": d.get("uploaded_by"),
                           "summary": (d.get("summary") or "")[:200]} for d in rows],
            "_refs": [{"id": str(d["_id"]), "title": d.get("title")} for d in rows[:8]],
        } if rows else {"documents": [], "note": "No documents have been uploaded yet."}

    if name == "search_documents":
        tokens = [t for t in re.findall(r"\w+", (args.get("query") or "").lower()) if len(t) >= 3]
        if not tokens:
            return {"error": "query is required"}
        scored = []
        for d in documents.find({}):
            title = (d.get("title") or "").lower()
            text = d.get("text") or ""
            low = text.lower()
            score = sum(5 for t in tokens if t in title) + sum(min(low.count(t), 10) for t in tokens)
            if score:
                scored.append((score, d, text))
        scored.sort(key=lambda s: s[0], reverse=True)
        top = scored[:3]
        if not top:
            return {"matches": [], "note": "No document matches."}
        return {
            "matches": [{"id": str(d["_id"]), "title": d.get("title"),
                         "uploaded_at": (d.get("uploaded_at") or "")[:10],
                         "snippet": _snippet(text, tokens)} for _s, d, text in top],
            "_refs": [{"id": str(d["_id"]), "title": d.get("title")} for _s, d, _t in top],
        }

    if name == "get_document":
        try:
            doc = documents.find_one({"_id": ObjectId((args.get("document_id") or "").strip())})
        except Exception:  # noqa: BLE001
            doc = None
        if not doc:
            return {"error": "Document not found."}
        ref = [{"id": str(doc["_id"]), "title": doc.get("title")}]
        text = doc.get("text") or ""
        if not text:
            return {"title": doc.get("title"), "note": "This file has no readable text (it may be a "
                    "scan), so it can only be downloaded.", "_refs": ref}
        offset = max(0, int(args.get("offset") or 0))
        end = offset + DOCUMENT_READ_CHARS
        return {"title": doc.get("title"), "uploaded_at": (doc.get("uploaded_at") or "")[:10],
                "offset": offset, "total_chars": len(text), "text": text[offset:end],
                "next_offset": end if end < len(text) else None, "_refs": ref}

    return {"error": f"Unknown tool {name}"}


def _chat_with_documents(system_prompt, messages, extra_tools=None, run_extra=None):
    """The chatbot tool loop with the document tools always added. Returns
    (reply_text, [{id, title}, ...]) - the documents the bot looked at, for
    the Download buttons."""
    used = {}

    def runner(name, args):
        if name in _DOCUMENT_TOOL_NAMES:
            out = _run_document_tool(name, args)
            for ref in out.pop("_refs", []):
                used[ref["id"]] = ref
            return out
        if run_extra is None:
            return {"error": f"Unknown tool {name}"}
        return run_extra(name, args)

    reply = _chat_with_tools(system_prompt + DOCUMENT_PROMPT, messages,
                             list(extra_tools or []) + DOCUMENT_TOOLS, runner)
    return reply, list(used.values())[:8]


@app.post("/api/it/chat")
@require_it
def it_chat():
    body = request.get_json(silent=True) or {}
    message = (body.get("message") or "").strip()
    history = body.get("history") or []
    if not message:
        return jsonify({"message": "message is required."}), 400

    system_prompt = (
        "You are the SELMS IT Assistant, helping an IT staff member inside the Smart Employee "
        "Lifecycle Management System. Right now your job is finding and sharing company documents "
        "(IT policy, acceptable-use rules, forms, templates). For anything else, say you can only "
        "help with documents at the moment. Keep answers short and direct."
    )
    anthropic_messages = [{"role": m["role"], "content": m["content"]}
                          for m in history if m.get("role") in ("user", "assistant")]
    anthropic_messages.append({"role": "user", "content": message})

    try:
        reply, docs = _chat_with_documents(system_prompt, anthropic_messages)
    except Exception as exc:
        return jsonify({"message": f"Could not reach the assistant: {exc}"}), 502
    return jsonify({"reply": reply, "documents": docs}), 200


if __name__ == "__main__":
    # The auto-reloader is off on purpose. It watched Python's own library
    # files and restarted the server in the middle of a request whenever a
    # module was loaded for the first time (e.g. the first "Send email"), which
    # showed up as random errors in the app. Restart the backend by hand after
    # changing this file.
    threading.Thread(target=_reminder_loop, daemon=True).start()
    app.run(host="0.0.0.0", port=5000, debug=True, use_reloader=False)
