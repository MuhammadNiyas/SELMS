"""Resets SELMS to "zero activity" for a fresh test run.

KEPT:    employees (and the HR / IT accounts), equipment, human chat messages,
         the onboarding / offboarding flow charts (templates), files attached
         to flow steps, the company library, and the Google connection.
REMOVED: onboarding + offboarding progress, each person's own copy of the
         flows, bookings (and their Google Calendar events), shipments,
         notifications, system request cards, documents and surveys given to
         employees (with the files they uploaded), and equipment assignments.

A JSON backup of EVERYTHING is written to selms-backend/backups first.
Run it with the backend STOPPED:   python scripts/reset_activity.py
"""
import os
import sys
from datetime import datetime

BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(BACKEND)
sys.path.insert(0, BACKEND)

from bson import json_util  # noqa: E402

import selms_backend as b  # noqa: E402  (connects to MongoDB, starts nothing)

db = b.db

# ---- backup first
backup_dir = os.path.join(BACKEND, "backups")
os.makedirs(backup_dir, exist_ok=True)
stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
path = os.path.join(backup_dir, f"selms-backup-{stamp}.json")
dump = {name: list(db[name].find()) for name in db.list_collection_names()}
with open(path, "w", encoding="utf-8") as fh:
    fh.write(json_util.dumps(dump, indent=1))
print("backup:", path)

# ---- Google Calendar events of the bookings about to be removed
removed_events = 0
for booking in dump.get("bookings", []):
    event_id = booking.get("google_event_id")
    if event_id:
        try:
            b._delete_google_event(event_id)
            removed_events += 1
        except Exception as exc:  # noqa: BLE001
            print("  could not remove a Google event:", exc)
print("Google events removed:", removed_events)

# ---- files employees uploaded back
for rec in dump.get("flow_documents", []):
    name = rec.get("returned_stored_name")
    if name:
        try:
            os.remove(os.path.join(b.PRIVATE_FOLDER, name))
        except OSError:
            pass

print("bookings:", db.bookings.delete_many({}).deleted_count)
print("shipments:", db.shipments.delete_many({}).deleted_count)
print("notifications:", db.notifications.delete_many({}).deleted_count)
print("password reset codes:", db.password_resets.delete_many({}).deleted_count)
print("system request cards:", db.messages.delete_many({"sender_role": "system"}).deleted_count)
print("employees' own onboarding flows:", db.onboarding_flows.delete_many({"_id": {"$ne": "template"}}).deleted_count)
print("employees' own offboarding flows:", db.offboarding_flows.delete_many({"_id": {"$ne": "template"}}).deleted_count)
print("documents given out:", db.flow_documents.delete_many({}).deleted_count)
print("surveys given out:", db.flow_surveys.delete_many({}).deleted_count)

r = db.users.update_many({"role": "employee"}, {
    "$unset": {
        "onboarding_status": "", "offboarding_status": "", "last_working_day": "",
        "signed_documents": "", "notifications_read_at": "",
        "seen_at.onboarding": "", "seen_at.offboarding": "", "seen_at.documents": "",
    },
    "$set": {"must_change_password": False},
})
print("employees reset:", r.modified_count)

r = db.equipment.update_many({}, {
    "$set": {"status": "available", "assigned_to_employee_id": None, "assigned_to_employee_name": None,
             "assigned_to_employee_department": None, "assigned_to_employee_photo_url": None,
             "assigned_date": None, "assignment_notes": None},
    "$unset": {"last_return_notes": "", "last_returned_date": ""},
})
print("equipment unassigned:", r.modified_count)

print("\nnow in the database:")
for name in sorted(db.list_collection_names()):
    print(f"  {name}: {db[name].count_documents({})}")
