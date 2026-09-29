const { getDatabase, initClefbase } = require('clefbase');

let companyCollection;

function getCompanyCollection() {
  if (companyCollection) return companyCollection;

  const { CLEFBASE_SERVER_URL, CLEFBASE_PROJECT_ID, CLEFBASE_API_KEY } =
    process.env;

  if (!CLEFBASE_PROJECT_ID || !CLEFBASE_API_KEY) {
    throw new Error(
      'ClefBase is not configured. Set CLEFBASE_PROJECT_ID and CLEFBASE_API_KEY.',
    );
  }

  const app = initClefbase({
    serverUrl: CLEFBASE_SERVER_URL || 'https://api.cleforyx.com',
    projectId: CLEFBASE_PROJECT_ID,
    apiKey: CLEFBASE_API_KEY,
  });

  companyCollection = getDatabase(app).collection('companies');
  return companyCollection;
}

function companyDocumentId(companyNameLower) {
  return encodeURIComponent(companyNameLower);
}

async function registerCompany({ companyName, username }) {
  const name = companyName.trim();
  const nameLower = name.toLowerCase();
  const company = getCompanyCollection().doc(companyDocumentId(nameLower));
  const existing = await company.get();
  const details = {
    name,
    nameLower,
    username: username.trim(),
  };

  if (existing) {
    await company.update(details);
  } else {
    await company.set({ ...details, paid: false });
  }
}

async function markCompanyPaid(companyNameLower, payment) {
  const company = getCompanyCollection().doc(
    companyDocumentId(companyNameLower.trim().toLowerCase()),
  );
  const existing = await company.get();
  if (!existing) return false;
  if (existing.paymentReference === payment.reference) return true;

  const customFields = payment.metadata?.custom_fields || [];
  const planField = customFields.find((field) => field.variable_name === 'plan');
  const isYearly =
    planField?.value === 'yearly' || Number(payment.amount) === 36000;
  const paidAt = new Date();
  const expiresAt = new Date(paidAt);
  expiresAt.setDate(expiresAt.getDate() + (isYearly ? 365 : 30));

  await company.update({
    paid: true,
    plan: isYearly ? 'yearly' : 'monthly',
    paymentReference: payment.reference || null,
    paidAt: paidAt.toISOString(),
    expiresAt: expiresAt.toISOString(),
  });
  return true;
}

async function getCompanyStatus(companyName) {
  const company = getCompanyCollection().doc(
    companyDocumentId(companyName.trim().toLowerCase()),
  );
  const existing = await company.get();
  if (!existing) return null;
  const expiresAt = existing.expiresAt ? new Date(existing.expiresAt) : null;
  const paid =
    existing.paid === true && (!expiresAt || expiresAt > new Date());
  return {
    paid,
    plan: existing.plan || null,
    expiresAt: existing.expiresAt || null,
  };
}

module.exports = {
  getCompanyStatus,
  markCompanyPaid,
  registerCompany,
};
