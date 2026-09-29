# Payment Deployment Checklist

## Secrets

- Store the selected USSD provider credentials in the hosting provider's secret manager.
- Do not deploy `backend/.env` or the Firebase service-account JSON file.
- Use a server-managed Firebase service account in production.

## Backend environment

```env
PORT=3000
APP_ORIGIN=https://your-app-domain.example
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_SERVICE_ACCOUNT_PATH=
```

## USSD provider

The backend currently returns a clear `501` response until a USSD provider is
selected and its initialization and webhook APIs are implemented.

## Flutter

Build with the deployed API URL:

```powershell
flutter build windows --dart-define=PAYMENT_BACKEND_URL=https://your-api-domain.example/api/payments/initialize
```

Never put payment-provider secret keys in Flutter.

## Firebase

Create Firestore rules that prevent public reads and writes to `subscriptions` and
`payment_events`. Only the backend service account should write payment records.

The repository includes `firestore.rules` for these payment collections. Deploy it
with the Firebase CLI from the repository root after selecting the correct project.