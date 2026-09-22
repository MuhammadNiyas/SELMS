"""
scripts/seed_account.py

Run this to create the very first HR admin account, or the very first IT
staff account, for SELMS. Replaces the old separate seed_admin.py and
seed_it.py — same secure pattern for both, just asks which role first.

Credentials are always typed live in the terminal, never hardcoded in this
file or written anywhere in plain text. The password is hashed immediately
and only the hash is stored in MongoDB.

This is meant for bootstrapping only — the very first account of each
role. Every account after that should be created from inside the app
itself by an HR admin (Add Employee already works this way; an equivalent
"Add IT staff" screen is the intended long-term way to add more IT
accounts, rather than running this script again).

Usage (run from the project root, selms-backend/):
    python scripts/seed_account.py

Requires: pymongo, bcrypt
    pip install pymongo bcrypt --break-system-packages
"""

import os
import sys
import getpass
from datetime import datetime, timezone

import bcrypt
from pymongo import MongoClient

MONGO_URI = os.environ.get("MONGO_URI", "mongodb://localhost:27017")
DB_NAME = os.environ.get("SELMS_DB", "selms")

ROLE_LABELS = {"hr": "HR admin", "it": "IT staff"}


def _choose_role() -> str:
    print("Which account do you want to create?")
    print("  1. HR admin")
    print("  2. IT staff")
    while True:
        choice = input("Enter 1 or 2: ").strip()
        if choice == "1":
            return "hr"
        if choice == "2":
            return "it"
        print("Please type 1 or 2.")


def seed_account():
    role = _choose_role()
    label = ROLE_LABELS[role]

    client = MongoClient(MONGO_URI)
    db = client[DB_NAME]
    users = db["users"]

    # One-time-only guard, scoped to whichever role was chosen — an HR
    # account already existing doesn't block seeding the first IT account,
    # and vice versa.
    if users.find_one({"role": role}):
        print(f"\nAn {label} account already exists. Refusing to seed a second one.")
        print(f"Create additional {label} accounts from inside the app instead.")
        sys.exit(1)

    print(f"\nCreating the first {label} account for SELMS.\n")
    full_name = input("Full name: ").strip()
    email = input("Work email: ").strip().lower()
    password = getpass.getpass("Password: ")
    confirm = getpass.getpass("Confirm password: ")

    if password != confirm:
        print("Passwords did not match. Aborting.")
        sys.exit(1)
    if len(password) < 8:
        print("Password must be at least 8 characters. Aborting.")
        sys.exit(1)

    password_hash = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt())

    users.insert_one({
        "full_name": full_name,
        "email": email,
        "password_hash": password_hash,
        "role": role,            # hr | it | employee
        "is_admin_seed": True,   # marks this as an original seeded account
        "created_at": datetime.now(timezone.utc),
    })

    print(f"\nDone. {label} account '{email}' can now log in on the {label.split()[0]} tab.")


if __name__ == "__main__":
    seed_account()
