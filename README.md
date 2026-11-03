# SELMS — Smart Employee Lifecycle Management System

SELMS is a Final Year Project that helps a company manage employee onboarding
and offboarding in one place. It connects HR, IT and employees, so tasks,
meetings and company equipment are tracked instead of being handled by email
and spreadsheets.

## Who uses it

| Role | What they do |
|---|---|
| HR | Registers employees, starts onboarding and offboarding, manages the schedule and monitors progress |
| IT | Assigns and receives equipment, handles requests and Pos Malaysia parcels |
| Employee | Follows their steps, completes documents and surveys, joins meetings and returns equipment |

## How it works

**Onboarding**
1. HR registers the employee and sets up their onboarding flow.
2. HR reviews the steps and presses Start.
3. SELMS sends the welcome email and books the orientation in a free time slot.
4. IT is told what equipment to prepare, then assigns it. Remote employees receive it by Pos Malaysia.
5. The employee completes their documents and survey.
6. When every step is done, onboarding is marked complete.

**Offboarding**
1. HR enters the departure type and last working day, then presses Start.
2. SELMS sends the offboarding email and books the exit interview.
3. The employee completes a checklist for each item and returns it.
   Remote employees post it and send IT the tracking number and QR code.
4. IT receives each item, or records it as damaged or lost.
5. IT access is revoked, and the employee's login closes after the last working day.

## Main features

- **Flow builder:** set the steps and timing for onboarding and offboarding
- **Smart scheduling:** refuses clashing times and finds the next free slot
- **Equipment tracking:** tracks each item by QR code and asset tag
- **Shipments:** records Pos Malaysia parcels for remote employees
- **Dashboards:** show progress and On track, At risk or Delayed status
- **Notifications:** in-app alerts, reminders and emails
- **AI chatbot:** answers common questions from company information

## Technology

- **App:** Flutter (web)
- **Backend:** Python, Flask
- **Database:** MongoDB
- **AI:** Claude API
- **Meetings:** Google Calendar and Google Meet
- **Email:** Gmail SMTP

## How to run it

You need Flutter, Python and a MongoDB database.

**1. Start the backend**

```
cd selms/selms-backend
pip install flask flask-cors pymongo bcrypt pyjwt openpyxl pypdf python-docx python-dotenv
copy .env.example .env
```

Open `.env` and fill in your own values, then run:

```
python scripts/seed_account.py
python selms_backend.py
```

The seed script creates the first HR account. Run it again to create the first
IT account. The backend runs at http://localhost:5000.

**2. Start the app**

Open a second terminal:

```
cd selms/selms
flutter pub get
flutter run -d chrome
```

Sign in with the HR or IT account you created. Employee accounts are created by HR.

## Limitations

- Pos Malaysia parcels are booked on the Pos website, then recorded in SELMS.
- Google Meet links need a connected Google account.
- The chatbot only answers from company information it has been given.
- Meetings run from 10 AM to 5 PM, Monday to Friday, on one shared schedule.
- Work email accounts are created manually by IT.
