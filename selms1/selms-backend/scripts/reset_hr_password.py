"""
scripts/reset_hr_password.py

Use this if you've forgotten your HR admin password. It cannot be
recovered (it's stored as a one-way bcrypt hash) — this resets it to a
new one you choose.

Usage (run from selms-backend/):
    python scripts/reset_hr_password.py

Requires: pymongo, bcrypt
    pip install pymongo bcrypt --break-system-packages
"""

import os
import sys
import getpass

import bcrypt
from pymongo import MongoClient

MONGO_URI = os.environ.get("MONGO_URI", "mongodb://localhost:27017")
DB_NAME = os.environ.get("SELMS_DB", "selms")


def reset_hr_password():
    client = MongoClient(MONGO_URI)
    db = client[DB_NAME]
    users = db["users"]

    hr_user = users.find_one({"role": "hr"})
    if not hr_user:
        print("No HR account found in the database.")
        sys.exit(1)

    print(f"Resetting password for HR account: {hr_user['email']}\n")
    password = getpass.getpass("New password: ")
    confirm = getpass.getpass("Confirm new password: ")

    if password != confirm:
        print("Passwords did not match. Aborting.")
        sys.exit(1)
    if len(password) < 8:
        print("Password must be at least 8 characters. Aborting.")
        sys.exit(1)

    password_hash = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt())
    users.update_one({"_id": hr_user["_id"]}, {"$set": {"password_hash": password_hash}})

    print(f"\nDone. You can now log in as '{hr_user['email']}' with the new password.")


if __name__ == "__main__":
    reset_hr_password()
