# SELMS — Smart Employee Lifecycle Management System

Two independent projects, kept separate on purpose:

```
selms/               Flutter app
selms-backend/        Flask API + one-time admin seed script
```

## What's in the Flutter app

```
lib/
├── main.dart
├── theme/selms_colors.dart          Shared black-sidebar / light-blue palette
├── models/employee.dart
├── services/api_client.dart         All HTTP calls to the backend
├── widgets/
│   ├── app_shell.dart                Sidebar + top bar, reused by every HR screen
│   └── form_fields.dart              Shared text/dropdown/date field widgets
└── screens/
    ├── selms_login_screen.dart       HR / IT / Employee role tabs, no self-registration
    ├── dashboard_screen.dart         "Welcome, admin" + placeholder for future charts
    ├── employee_directory_screen.dart Universal search + 4-field filter panel + card grid
    ├── employee_view_screen.dart     Full read-only details, Edit + Delete
    ├── employee_edit_screen.dart     Same fields, pre-filled, no re-triggered onboarding
    ├── add_employee_screen.dart      Full 3-section form, employee-only
    └── review_employee_screen.dart   Safety checkpoint before onboarding fires
```

**Search is universal** — it matches against every field on the backend
(name, ID, department, job title, work location, employment status, emails,
phone, line manager, IC/passport). The Filters panel only narrows by three
specific categories (Department, Employment status, Work location type) and
works independently of search.

**Onboarding only fires for employee accounts, only once, only after
Review.** Add Employee -> fill in all fields -> Review screen (shows a
summary, confirms nothing has happened yet) -> Confirm and create -> record
saves -> (in a real deploy) welcome email + IT equipment task + auto-scheduled
orientation happen as a follow-up step, not blocking account creation.
Editing an employee afterwards never re-triggers this chain.

## 1. Start the backend

```bash
cd selms-backend
pip install flask flask-cors pymongo bcrypt pyjwt openpyxl pypdf python-docx --break-system-packages

export MONGO_URI="mongodb://localhost:27017"
export JWT_SECRET="change-this-in-production"

# Real email sending — free, no Microsoft tenant needed. Use any Gmail
# account: turn on 2-factor auth, then generate an "App Password" at
# https://myaccount.google.com/apppasswords and use that (not your normal
# Gmail password) below.
export SMTP_HOST="smtp.gmail.com"
export SMTP_PORT="587"
export SMTP_USER="youraccount@gmail.com"
export SMTP_PASSWORD="your-16-character-app-password"
export SMTP_FROM_NAME="SELMS HR"

# Optional — AI-drafted welcome emails. If not set, a fixed template is
# used instead (HR still reviews/edits it before sending either way).
export ANTHROPIC_API_KEY="your-key-here"

python selms_backend.py            # starts the API on http://localhost:5000
```

## Onboarding — how it actually works now

**Employees (sidebar) is registration-only.** Adding an employee no longer
auto-starts onboarding — it just creates the record.

**Onboarding (sidebar) is where HR deliberately starts it:**
1. Pick a registered employee from the list, click "Start onboarding"
2. Review the AI-drafted (or template) welcome email — edit it, regenerate
   it with an instruction, or leave it as-is
3. Click "Send email" — only now does anything actually happen
4. Land on a vertical, click-to-expand progress stepper: Registered →
   Welcome email sent → Email confirmed → IT equipment ready → Orientation
   scheduled

"Email confirmed" flips automatically and for real — the email includes a
link that hits a public backend endpoint
(`GET /api/onboarding/confirm/<token>`) when the employee clicks it, no
login required on their end. The last two steps (IT equipment, orientation)
are marked done manually by HR for now, since the actual IT and Smart
Scheduling modules aren't built yet — see the code comments in
`selms_backend.py` for exactly where those would plug in.

(You've already run `scripts/seed_account.py` — no need to run it again for
HR. It refuses to run a second time for a role that already exists.)

## 2. Run the Flutter app

```bash
cd selms
flutter pub get
flutter run -d chrome              # or your device/emulator of choice
```

`lib/main.dart` points at `http://localhost:5000` by default — change
`apiBaseUrl` there once you deploy the backend somewhere other than your own
machine. If running on an Android emulator, use `http://10.0.2.2:5000`
instead of `localhost`.

## API summary

| Method | Route | Who | Purpose |
|---|---|---|---|
| POST | `/api/auth/login` | anyone | role + email + password -> JWT |
| POST | `/api/employees` | HR | create employee, triggers onboarding |
| GET | `/api/employees` | HR | list + universal search (`q=`) + filters |
| GET | `/api/employees/<id>` | HR | full detail |
| PUT | `/api/employees/<id>` | HR | edit, optional password reset |
| DELETE | `/api/employees/<id>` | HR | requires `confirm_employee_id` in body |
| POST | `/api/employees/<id>/photo` | HR | multipart profile photo upload (JPG/PNG, up to 5MB) |
| GET | `/uploads/<filename>` | anyone | serves uploaded profile photos back out |

### Recent changes to the employee record

- `home_address` was split into `address_line`, `postcode`, and `state`
  (state is a dropdown of Malaysian states in the app).
- `bank_account_number` and `epf_socso_tax_no` were removed.
- Added `emergency_contact_relationship`.
- Added `profile_image_url` — set by the photo upload endpoint above, not
  sent as part of the create/edit form payload. Photos are saved as plain
  files under `selms-backend/uploads/` (set `SELMS_UPLOAD_FOLDER` to
  change that path) and served back out at `/uploads/<filename>`.

## Notes

- There is no self-registration on the login screen. The first HR account
  comes from `scripts/seed_account.py` (choose "HR admin" when prompted);
  the first IT account comes from the same script (choose "IT staff").
  Every account after that is an Employee account created by HR from
  inside the app.
- HR and IT accounts aren't created through the login UI or self-service —
  the first of each comes from `scripts/seed_account.py`, and only
  Employee accounts are created afterwards, via Add Employee.
- `selms-backend/` is plain Python, not a Flutter package — that's why it
  lives outside `selms/` rather than inside `lib/`.
