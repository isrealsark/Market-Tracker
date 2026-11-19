# Deployment

## Backend secrets

Keep `backend/.env` out of source control. Configure these values in the deployment host's secret manager:

```env
PORT=3000
APP_ORIGIN=https://your-app-domain.example
CLEFBASE_SERVER_URL=https://api.cleforyx.com
CLEFBASE_PROJECT_ID=your_clefbase_project_id
CLEFBASE_API_KEY=your_clefbase_server_api_key
PAYSTACK_SECRET_KEY=your_paystack_secret_key
```

The Clefbase API key is server-only; never include it in the Flutter app. Rotate any credentials that were previously committed in `.env.example`.
Admin sign-in is checked locally by the Flutter app and does not use the backend.
Because client-side credentials can be extracted from an installed app, this is
not suitable for protecting sensitive administrative functions.

## Paystack setup

Set the Paystack webhook URL to `https://your-api-domain.example/paystack/webhook`.
Both hosted Paystack pages must include a required custom field with variable name
exactly `company_name`. The webhook matches that value to the registered company
and derives the plan from the verified GHS amount: `3000` monthly or `36000` yearly.
Keep both hosted links configured for those exact amounts and enable the payment
channels shown by the app.

Because these are static hosted links, the buyer enters the company name on Paystack;
this payment association is less strong than a per-company transaction reference.

## Flutter Windows build

Build with the deployed backend URL:

```powershell
flutter build windows --release --dart-define=BACKEND_URL=https://your-api-domain.example
```

## Existing local accounts

Back up the SQLite database before migration. Each company owner must sign in online first with the existing company name, username, and PIN. That first sign-in claims the Clefbase company record and uploads the local company data. Workers and additional devices can sign in after the owner migration completes.

The desktop app keeps a local SQLite copy for offline use and retries pending snapshot uploads when online. Do not delete local database files until the cloud data has been verified.
