const crypto = require('crypto');
const { getDatabase: createDatabase, initClefbase } = require('clefbase');

let companyCollection;
let clefbaseDatabase;
const companyDataCollections = [
  'users',
  'workers',
  'customers',
  'products',
  'sales',
  'payments',
  'expenses',
  'debts',
  'receipts',
];

function getClefbaseDatabase() {
  if (clefbaseDatabase) return clefbaseDatabase;

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

  clefbaseDatabase = createDatabase(app);
  companyCollection = clefbaseDatabase.collection('companies');
  return clefbaseDatabase;
}

function getCompanyCollection() {
  if (companyCollection) return companyCollection;
  getClefbaseDatabase();
  return companyCollection;
}

function companyDocumentId(companyNameLower) {
  return encodeURIComponent(companyNameLower);
}

async function findCompanyByName(companyNameLower) {
  const matches = await getCompanyCollection()
    .where({ nameLower: companyNameLower })
    .limit(1)
    .getDocs();
  if (matches.length === 0) return null;
  return {
    data: matches[0],
    reference: getCompanyCollection().doc(matches[0]._id),
  };
}

async function registerCompany({ companyName, username }) {
  const name = companyName.trim();
  const nameLower = name.toLowerCase();
  const company = getCompanyCollection().doc(companyDocumentId(nameLower));
  const existing = await company.get();
  if (existing) return false;

  await company.set({
    name,
    nameLower,
    username: username.trim(),
    paid: false,
    dataRevision: 0,
  });
  return true;
}

function hashCompanyPin(pin, salt) {
  return crypto.scryptSync(pin, salt, 64).toString('hex');
}

function verifyCompanyPin(pin, salt, expectedHash) {
  if (!salt || !expectedHash) return false;
  const actual = Buffer.from(hashCompanyPin(pin, salt), 'hex');
  const expected = Buffer.from(expectedHash, 'hex');
  return actual.length === expected.length && crypto.timingSafeEqual(actual, expected);
}

async function signInCompany({ companyName, username, pin }) {
  const normalizedCompany = companyName.trim().toLowerCase();
  const normalizedUsername = username.trim().toLowerCase();
  const suppliedPin = typeof pin === 'string' ? pin.trim() : '';
  if (suppliedPin.length > 0 && !/^\d{4}$/.test(suppliedPin)) return null;

  const foundCompany = await findCompanyByName(normalizedCompany);
  if (!foundCompany) return null;
  const { data: company, reference: companyRef } = foundCompany;
  const companyId = companyRef.id;

  const isOwner = company.username?.trim().toLowerCase() === normalizedUsername;
  const workers = isOwner
    ? []
    : await companyRef
        .subcollection('workers')
        .where({ loginName: normalizedUsername })
        .limit(1)
        .getDocs();
  if (!isOwner && workers.length === 0) return null;

  let credentialsValid = suppliedPin.length === 0;
  if (suppliedPin.length > 0) {
    const salt = crypto.randomBytes(16).toString('hex');
    const candidateHash = hashCompanyPin(suppliedPin, salt);
    credentialsValid = await getClefbaseDatabase().runTransaction(
      async (transaction) => {
        const current = await transaction.get(companyRef);
        if (!current) return false;

        if (current.pinHash) {
          return verifyCompanyPin(suppliedPin, current.pinSalt, current.pinHash);
        }

        if (!isOwner) return false;
        transaction.update(companyRef, { pinSalt: salt, pinHash: candidateHash });
        return true;
      },
    );
  }
  if (!credentialsValid) return null;

  const token = crypto.randomBytes(32).toString('base64url');
  const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
  const session = {
    companyId,
    companyName: company.name,
    username: username.trim(),
    role: isOwner ? 'owner' : 'worker',
    needsMigration: !company.dataMigratedAt,
    expiresAt: expiresAt.toISOString(),
  };
  await getClefbaseDatabase()
    .collection('sessions')
    .doc(crypto.createHash('sha256').update(token).digest('hex'))
    .set(session);

  return { token, ...session };
}

async function getCompanySession(token) {
  if (!token) return null;
  const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
  const session = await getClefbaseDatabase()
    .collection('sessions')
    .doc(tokenHash)
    .get();
  if (!session || Date.parse(session.expiresAt) <= Date.now()) return null;
  return session;
}

async function revokeCompanySession(token) {
  if (!token) return;
  const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
  await getClefbaseDatabase()
    .collection('sessions')
    .doc(tokenHash)
    .delete();
}

function sanitizeCompanyRow(collectionName, row) {
  const copy = { ...row };
  if (collectionName === 'users') {
    delete copy.pinHash;
    delete copy.subscriptionPaid;
    delete copy.subscriptionExpiresAt;
  }
  return copy;
}

async function getCompanyData(companyId) {
  const company = getCompanyCollection().doc(companyId);
  const companyRecord = await company.get();
  if (!companyRecord) return null;
  const lockExpiry = Date.parse(companyRecord.syncLockExpiresAt || '');
  if (Number.isFinite(lockExpiry) && lockExpiry > Date.now()) {
    const busy = new Error('Company data is being synchronized.');
    busy.code = 'SNAPSHOT_BUSY';
    throw busy;
  }
  const snapshot = {};
  for (const collectionName of companyDataCollections) {
    const rows = await company
      .subcollection(collectionName)
      .getDocs();
    snapshot[collectionName] = rows.map((row) => {
      const copy = { ...row };
      delete copy._id;
      delete copy._createdAt;
      delete copy._updatedAt;
      delete copy.loginName;
      return copy;
    });
  }
  const latestCompany = await company.get();
  const latestLockExpiry = Date.parse(latestCompany?.syncLockExpiresAt || '');
  if (
    !latestCompany ||
    Number(latestCompany.dataRevision || 0) !==
      Number(companyRecord.dataRevision || 0) ||
    (Number.isFinite(latestLockExpiry) && latestLockExpiry > Date.now())
  ) {
    const busy = new Error('Company data changed during download.');
    busy.code = 'SNAPSHOT_BUSY';
    throw busy;
  }
  return {
    data: snapshot,
    revision: Number(companyRecord.dataRevision || 0),
  };
}

async function getCompanyDataRevision(companyId) {
  const company = getCompanyCollection().doc(companyId);
  const companyRecord = await company.get();
  return companyRecord ? Number(companyRecord.dataRevision || 0) : null;
}

async function replaceCompanyData(companyId, data, expectedRevision) {
  if (!Number.isInteger(expectedRevision) || expectedRevision < 0) {
    throw new Error('Invalid company data revision.');
  }
  const serialized = JSON.stringify(data);
  if (Buffer.byteLength(serialized, 'utf8') > 8 * 1024 * 1024) {
    throw new Error('Company data snapshot exceeds 8 MB.');
  }
  for (const collectionName of companyDataCollections) {
    const rows = data[collectionName];
    if (!Array.isArray(rows) || rows.length > 10000) {
      throw new Error(`Invalid ${collectionName} collection.`);
    }
    if (rows.some((row) => !row || typeof row !== 'object' || row.id == null)) {
      throw new Error(`Invalid row in ${collectionName} collection.`);
    }
  }

  const company = getCompanyCollection().doc(companyId);
  const lockToken = crypto.randomBytes(24).toString('hex');
  const database = getClefbaseDatabase();
  const lockExpiresAt = new Date(Date.now() + 5 * 60 * 1000).toISOString();
  let currentRevision;
  await database.runTransaction(async (transaction) => {
    const currentCompany = await transaction.get(company);
    if (!currentCompany) throw new Error('Company was not found.');
    currentRevision = Number(currentCompany.dataRevision || 0);
    const existingLockExpiry = Date.parse(currentCompany.syncLockExpiresAt || '');
    if (
      currentRevision !== expectedRevision ||
      (Number.isFinite(existingLockExpiry) && existingLockExpiry > Date.now())
    ) {
      const conflict = new Error('Company data changed on another device.');
      conflict.code = 'REVISION_CONFLICT';
      throw conflict;
    }
    transaction.update(company, { syncLockToken: lockToken, syncLockExpiresAt: lockExpiresAt });
  });

  try {
    for (const collectionName of companyDataCollections) {
      const rows = data[collectionName] ?? [];
      const collection = company.subcollection(collectionName);
      const existingRows = await collection.getDocs();
      const nextIds = new Set(rows.map((row) => String(row.id)));
      const staleIds = existingRows
        .map((row) => String(row.id ?? row._id))
        .filter((id) => !nextIds.has(id));
      for (let index = 0; index < staleIds.length; index += 500) {
        await collection.batchDelete(staleIds.slice(index, index + 500));
      }

      for (let index = 0; index < rows.length; index += 400) {
        const batch = database.batch();
        for (const row of rows.slice(index, index + 400)) {
          const sanitized = sanitizeCompanyRow(collectionName, row);
          if (collectionName === 'workers') {
            sanitized.loginName = String(row.name ?? '').trim().toLowerCase();
          }
          batch.set(collection.doc(String(row.id)), sanitized);
        }
        await batch.commit();
      }
    }

    const syncedAt = new Date().toISOString();
    await database.runTransaction(async (transaction) => {
      const currentCompany = await transaction.get(company);
      if (currentCompany?.syncLockToken !== lockToken) {
        throw new Error('Company data sync lease expired.');
      }
      transaction.update(company, {
        dataRevision: currentRevision + 1,
        lastDataSyncAt: syncedAt,
        dataMigratedAt: currentCompany.dataMigratedAt || syncedAt,
        syncLockToken: null,
        syncLockExpiresAt: null,
      });
    });
    return currentRevision + 1;
  } catch (error) {
    try {
      await database.runTransaction(async (transaction) => {
        const currentCompany = await transaction.get(company);
        if (currentCompany?.syncLockToken === lockToken) {
          transaction.update(company, {
            syncLockToken: null,
            syncLockExpiresAt: null,
          });
        }
      });
    } catch (_) {
      // The lease expires automatically if Clefbase is unreachable.
    }
    throw error;
  }
}

async function createPendingPayment({
  session,
  reference,
  amount,
  currency,
  plan,
}) {
  if (session.role !== 'owner') return false;
  const expectedAmount = plan === 'yearly' ? 36000 : 3000;
  if (!['monthly', 'yearly'].includes(plan) || amount !== expectedAmount) {
    return false;
  }

  const payment = getClefbaseDatabase()
    .collection('billing_payments')
    .doc(encodeURIComponent(reference));
  if (await payment.get()) return false;
  await payment.set({
    reference,
    companyId: session.companyId,
    plan,
    amount,
    currency,
    status: 'pending',
    createdAt: new Date().toISOString(),
  });
  return true;
}

async function markCompanyPaid(payment) {
  const reference = payment?.reference;
  if (typeof reference !== 'string' || !reference) return false;

  const database = getClefbaseDatabase();
  const pendingPayment = database
    .collection('billing_payments')
    .doc(encodeURIComponent(reference));
  const result = await database.runTransaction(async (transaction) => {
    const storedPayment = await transaction.get(pendingPayment);
    if (!storedPayment) return false;
    if (storedPayment.status === 'paid') return true;
    if (
      payment.status !== 'success' ||
      payment.reference !== storedPayment.reference ||
      payment.currency !== storedPayment.currency ||
      Number(payment.amount) !== storedPayment.amount
    ) {
      return false;
    }

    const expectedAmount = storedPayment.plan === 'yearly' ? 36000 : 3000;
    if (storedPayment.amount !== expectedAmount) return false;

    const company = getCompanyCollection().doc(storedPayment.companyId);
    const companyData = await transaction.get(company);
    if (!companyData) return false;

    const now = new Date();
    const currentExpiry = companyData.paid && companyData.expiresAt
      ? new Date(companyData.expiresAt)
      : now;
    const baseDate = currentExpiry > now ? currentExpiry : now;
    const expiresAt = new Date(baseDate);
    expiresAt.setDate(
      expiresAt.getDate() + (storedPayment.plan === 'yearly' ? 365 : 30),
    );

    transaction.update(company, {
      paid: true,
      plan: storedPayment.plan,
      paymentReference: reference,
      paidAt: now.toISOString(),
      expiresAt: expiresAt.toISOString(),
    });
    transaction.update(pendingPayment, {
      status: 'paid',
      paidAt: now.toISOString(),
    });
    return true;
  });
  return result === true;
}

async function markCompanyPaidFromStaticLink(companyName, payment) {
  if (
    typeof companyName !== 'string' ||
    payment?.status !== 'success' ||
    payment?.currency !== 'GHS' ||
    typeof payment?.reference !== 'string' ||
    !payment.reference
  ) {
    return false;
  }

  const amount = Number(payment.amount);
  const plan = amount === 36000 ? 'yearly' : amount === 3000 ? 'monthly' : null;
  if (!plan) return false;

  const foundCompany = await findCompanyByName(companyName.trim().toLowerCase());
  if (!foundCompany) return false;
  const { reference } = foundCompany;
  const database = getClefbaseDatabase();
  const paymentReceipt = database
    .collection('processed_payments')
    .doc(encodeURIComponent(payment.reference));

  return database.runTransaction(async (transaction) => {
    const processedPayment = await transaction.get(paymentReceipt);
    if (processedPayment) return processedPayment.companyId === reference.id;

    const currentCompany = await transaction.get(reference);
    if (!currentCompany) return false;

    const now = new Date();
    const currentExpiry = currentCompany.paid && currentCompany.expiresAt
      ? new Date(currentCompany.expiresAt)
      : now;
    const baseDate = currentExpiry > now ? currentExpiry : now;
    const expiresAt = new Date(baseDate);
    expiresAt.setDate(expiresAt.getDate() + (plan === 'yearly' ? 365 : 30));

    transaction.update(reference, {
      paid: true,
      plan,
      paymentReference: payment.reference,
      paidAt: now.toISOString(),
      expiresAt: expiresAt.toISOString(),
    });
    transaction.set(paymentReceipt, {
      companyId: reference.id,
      reference: payment.reference,
      amount,
      currency: payment.currency,
      plan,
      processedAt: now.toISOString(),
    });
    return true;
  });
}

async function getCompanyStatus(companyName) {
  const foundCompany = await findCompanyByName(
    companyName.trim().toLowerCase(),
  );
  if (!foundCompany) return null;
  const { data: existing } = foundCompany;
  const expiresAt = existing.expiresAt ? new Date(existing.expiresAt) : null;
  const paid =
    existing.paid === true && (!expiresAt || expiresAt > new Date());
  return {
    paid,
    plan: existing.plan || null,
    expiresAt: existing.expiresAt || null,
  };
}

async function updateCompanyAccount({
  session,
  companyName,
  username,
  oldPin,
  newPin,
}) {
  if (session.role !== 'owner') return false;
  const company = getCompanyCollection().doc(session.companyId);
  const existing = await company.get();
  if (!existing) return false;
  const changes = {};
  if (companyName != null && username != null) {
    changes.name = companyName.trim();
    changes.nameLower = companyName.trim().toLowerCase();
    changes.username = username.trim();
  }
  if (newPin != null) {
    if (
      !/^\d{4}$/.test(oldPin ?? '') ||
      !/^\d{4}$/.test(newPin) ||
      !verifyCompanyPin(oldPin, existing.pinSalt, existing.pinHash)
    ) {
      return false;
    }
    const salt = crypto.randomBytes(16).toString('hex');
    changes.pinSalt = salt;
    changes.pinHash = hashCompanyPin(newPin, salt);
  }
  if (Object.keys(changes).length === 0) return false;

  const sessions = await getClefbaseDatabase()
    .collection('sessions')
    .where({ companyId: session.companyId })
    .getDocs();
  const batch = getClefbaseDatabase().batch();
  batch.update(company, changes);
  for (const activeSession of sessions) {
    const sessionChanges = {};
    if (changes.name) sessionChanges.companyName = changes.name;
    if (activeSession.role === 'owner' && changes.username) {
      sessionChanges.username = changes.username;
    }
    if (Object.keys(sessionChanges).length > 0) {
      batch.update(
        getClefbaseDatabase()
          .collection('sessions')
          .doc(activeSession._id),
        sessionChanges,
      );
    }
  }
  await batch.commit();
  return true;
}

module.exports = {
  createPendingPayment,
  getCompanyData,
  getCompanyDataRevision,
  getCompanySession,
  getCompanyStatus,
  markCompanyPaid,
  markCompanyPaidFromStaticLink,
  registerCompany,
  revokeCompanySession,
  replaceCompanyData,
  signInCompany,
  updateCompanyAccount,
};
