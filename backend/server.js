const path = require('path');
const https = require('node:https');
const crypto = require('node:crypto');
require('dotenv').config({
	path: path.join(__dirname, '.env'),
});

const express = require('express');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const helmet = require('helmet');
const {
	createPendingPayment,
	getCompanyData,
	getCompanyDataRevision,
	getCompanySession,
	getCompanyStatus,
	registerCompany,
	revokeCompanySession,
	replaceCompanyData,
	signInCompany,
	updateCompanyAccount,
} = require('./services/companyDatabase');
const paystackWebhook = require('./routes/webhook');

const app = express();
const port = Number(process.env.PORT || 3000);

app.set('trust proxy', 1);
app.use(helmet());
app.use(
	cors({
		origin: process.env.APP_ORIGIN || false,
	}),
);
app.use(paystackWebhook);
app.use(express.json({ limit: '10mb' }));

const plans = {
	monthly: { amount: 3000, currency: 'GHS' },
	yearly: { amount: 36000, currency: 'GHS' },
};

function initializePaystackTransaction(payload) {
	return new Promise((resolve, reject) => {
		const body = JSON.stringify(payload);
		const request = https.request(
			{
				hostname: 'api.paystack.co',
				path: '/transaction/initialize',
				method: 'POST',
				headers: {
					Authorization: `Bearer ${process.env.PAYSTACK_SECRET_KEY}`,
					'Content-Type': 'application/json',
					'Content-Length': Buffer.byteLength(body),
				},
			},
			(response) => {
				let responseBody = '';
				response.setEncoding('utf8');
				response.on('data', (chunk) => { responseBody += chunk; });
				response.on('end', () => {
					try {
						const result = JSON.parse(responseBody);
						if (response.statusCode < 200 || response.statusCode >= 300 || !result.status) {
						return reject(new Error('Paystack transaction initialization failed.'));
						}
						resolve(result.data);
					} catch (error) {
						reject(error);
					}
				});
			},
		);
		request.setTimeout(20000, () => request.destroy(new Error('Paystack request timed out.')));
		request.on('error', reject);
		request.write(body);
		request.end();
	});
}

const initializeLimiter = rateLimit({
	windowMs: 15 * 60 * 1000,
	limit: 10,
	standardHeaders: 'draft-8',
	legacyHeaders: false,
});

const companyRegistrationLimiter = rateLimit({
	windowMs: 15 * 60 * 1000,
	limit: 20,
	standardHeaders: 'draft-8',
	legacyHeaders: false,
});

const companyLoginLimiter = rateLimit({
	windowMs: 15 * 60 * 1000,
	limit: 10,
	standardHeaders: 'draft-8',
	legacyHeaders: false,
});

const accountUpdateLimiter = rateLimit({
	windowMs: 15 * 60 * 1000,
	limit: 10,
	standardHeaders: 'draft-8',
	legacyHeaders: false,
});

app.post('/api/auth/login', companyLoginLimiter, async (req, res) => {
	const { companyName, username, pin } = req.body;
	if (
		typeof companyName !== 'string' ||
		typeof username !== 'string' ||
		typeof pin !== 'string' ||
		companyName.trim().length < 2 ||
		companyName.trim().length > 100 ||
		username.trim().length < 2 ||
		username.trim().length > 100 ||
		(pin.length > 0 && !/^\d{4}$/.test(pin.trim()))
	) {
		return res.status(400).json({ message: 'Invalid company credentials.' });
	}

	try {
		const session = await signInCompany({
			companyName: companyName.trim(),
			username: username.trim(),
			pin,
		});
		if (!session) {
			return res.status(401).json({ message: 'Invalid company credentials.' });
		}
		return res.json(session);
	} catch (error) {
		console.error('Company login failed:', error);
		return res.status(503).json({ message: 'Could not sign in.' });
	}
});

app.get('/api/auth/session', async (req, res) => {
	const token = req.get('authorization')?.match(/^Bearer\s+(.+)$/i)?.[1];
	try {
		const session = await getCompanySession(token);
		if (!session) return res.status(401).json({ message: 'Session expired.' });
		return res.json(session);
	} catch (error) {
		console.error('Session lookup failed:', error);
		return res.status(503).json({ message: 'Could not check session.' });
	}
});

async function requireCompanySession(req, res, next) {
	const token = req.get('authorization')?.match(/^Bearer\s+(.+)$/i)?.[1];
	try {
		const session = await getCompanySession(token);
		if (!session) return res.status(401).json({ message: 'Session expired.' });
		req.companySession = session;
		return next();
	} catch (error) {
		console.error('Session validation failed:', error);
		return res.status(503).json({ message: 'Could not validate session.' });
	}
}

function requireCompanyOwner(req, res, next) {
	if (req.companySession?.role !== 'owner') {
		return res.status(403).json({ message: 'Owner access required.' });
	}
	return next();
}

app.delete('/api/auth/session', requireCompanySession, async (req, res) => {
	const token = req.get('authorization')?.match(/^Bearer\s+(.+)$/i)?.[1];
	try {
		await revokeCompanySession(token);
		return res.json({ revoked: true });
	} catch (error) {
		console.error('Session revocation failed:', error);
		return res.status(503).json({ message: 'Could not revoke session.' });
	}
});

app.get('/api/data/snapshot', requireCompanySession, async (req, res) => {
	try {
		const snapshot = await getCompanyData(req.companySession.companyId);
		if (!snapshot) return res.status(404).json({ message: 'Company not found.' });
		return res.json(snapshot);
	} catch (error) {
		console.error('Company data download failed:', error);
		return res.status(503).json({ message: 'Could not download company data.' });
	}
});

app.get('/api/data/revision', requireCompanySession, async (req, res) => {
	try {
		const revision = await getCompanyDataRevision(req.companySession.companyId);
		if (revision == null) return res.status(404).json({ message: 'Company not found.' });
		return res.json({ revision });
	} catch (error) {
		console.error('Company revision lookup failed:', error);
		return res.status(503).json({ message: 'Could not check company data revision.' });
	}
});

app.put('/api/data/snapshot', requireCompanySession, requireCompanyOwner, async (req, res) => {
	const data = req.body?.data;
	const expectedRevision = req.body?.revision;
	if (
		!data ||
		typeof data !== 'object' ||
		Array.isArray(data) ||
		!Number.isInteger(expectedRevision) ||
		expectedRevision < 0
	) {
		return res.status(400).json({ message: 'Invalid company data snapshot.' });
	}

	try {
		const revision = await replaceCompanyData(
			req.companySession.companyId,
			data,
			expectedRevision,
		);
		return res.json({ saved: true, revision });
	} catch (error) {
		console.error('Company data upload failed:', error);
		if (error.code === 'REVISION_CONFLICT') {
			return res.status(409).json({ message: error.message });
		}
		return res.status(400).json({ message: 'Could not save company data.' });
	}
});

app.put('/api/account', requireCompanySession, accountUpdateLimiter, async (req, res) => {
	const { companyName, username, oldPin, newPin } = req.body;
	const hasProfile = companyName != null || username != null;
	const hasPin = oldPin != null || newPin != null;
	if (
		(hasProfile && (
			typeof companyName !== 'string' ||
			typeof username !== 'string' ||
			companyName.trim().length < 2 ||
			companyName.trim().length > 100 ||
			username.trim().length < 2 ||
			username.trim().length > 100
		)) ||
		(hasPin && (
			typeof oldPin !== 'string' ||
			typeof newPin !== 'string' ||
			!/^\d{4}$/.test(oldPin) ||
			!/^\d{4}$/.test(newPin)
		)) ||
		(!hasProfile && !hasPin)
	) {
		return res.status(400).json({ message: 'Invalid account update.' });
	}

	try {
		const updated = await updateCompanyAccount({
			session: req.companySession,
			companyName: hasProfile ? companyName.trim() : null,
			username: hasProfile ? username.trim() : null,
			oldPin: hasPin ? oldPin : null,
			newPin: hasPin ? newPin : null,
		});
		if (!updated) return res.status(403).json({ message: 'Account update denied.' });
		return res.json({ updated: true });
	} catch (error) {
		console.error('Company account update failed:', error);
		return res.status(503).json({ message: 'Could not update company account.' });
	}
});

app.post('/api/companies/register', companyRegistrationLimiter, async (req, res) => {
	const { companyName, username } = req.body;
	const trimmedCompanyName = typeof companyName === 'string' ? companyName.trim() : '';
	const trimmedUsername = typeof username === 'string' ? username.trim() : '';

	if (
		trimmedCompanyName.length < 2 ||
		trimmedCompanyName.length > 100 ||
		trimmedUsername.length < 2 ||
		trimmedUsername.length > 100
	) {
		return res.status(400).json({ message: 'Invalid company registration.' });
	}

	try {
		const registered = await registerCompany({
			companyName: trimmedCompanyName,
			username: trimmedUsername,
		});
		if (!registered) {
			return res.status(409).json({ message: 'Company is already registered.' });
		}
		return res.status(201).json({ registered: true });
	} catch (error) {
		console.error('Company registration failed:', error);
		return res.status(500).json({ message: 'Could not register company.' });
	}
});

app.post('/api/companies/status', companyRegistrationLimiter, async (req, res) => {
	const companyName = typeof req.body.companyName === 'string'
		? req.body.companyName.trim()
		: '';

	if (companyName.length < 2 || companyName.length > 100) {
		return res.status(400).json({ message: 'Invalid company name.' });
	}

	try {
		const status = await getCompanyStatus(companyName);
		return res.json(status || { paid: false });
	} catch (error) {
		console.error('Company status lookup failed:', error);
		return res.status(503).json({ message: 'Could not check company status.' });
	}
});

app.post('/api/payments/initialize', requireCompanySession, requireCompanyOwner, initializeLimiter, async (req, res) => {
	const {
		fullName,
		phone,
		email,
		plan = 'monthly',
		paymentMethod = 'mobile_money',
	} = req.body;

	const trimmedName = typeof fullName === 'string' ? fullName.trim() : '';
	const trimmedPhone = typeof phone === 'string' ? phone.trim() : '';
	const trimmedEmail = typeof email === 'string' ? email.trim() : '';
	const validEmail = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmedEmail);
	const validPhone = /^[+]?[0-9 ()-]{7,20}$/.test(trimmedPhone);

	if (
		trimmedName.length < 2 ||
		trimmedName.length > 100 ||
		!validPhone ||
		!validEmail ||
		!plans[plan] ||
		!['mobile_money', 'bank_card'].includes(paymentMethod)
	) {
		return res.status(400).json({
			message: 'Invalid customer, plan, payment method, or backend configuration.',
		});
	}

	if (!process.env.PAYSTACK_SECRET_KEY) {
		return res.status(503).json({ message: 'Payment service is not configured.' });
	}

	const selectedPlan = plans[plan];
	const reference = `mt_${crypto.randomUUID()}`;
	try {
		const transaction = await initializePaystackTransaction({
			email: trimmedEmail,
			amount: selectedPlan.amount,
			currency: selectedPlan.currency,
			reference,
			channels: [paymentMethod === 'bank_card' ? 'card' : 'mobile_money'],
			metadata: {
				companyId: req.companySession.companyId,
				plan,
				fullName: trimmedName,
				phone: trimmedPhone,
			},
		});
		if (
			transaction.reference !== reference ||
			typeof transaction.authorization_url !== 'string'
		) {
			throw new Error('Paystack returned an invalid checkout session.');
		}

		const saved = await createPendingPayment({
			session: req.companySession,
			reference,
			amount: selectedPlan.amount,
			currency: selectedPlan.currency,
			plan,
		});
		if (!saved) throw new Error('Could not record checkout session.');

		return res.json({
			reference,
			authorizationUrl: transaction.authorization_url,
		});
	} catch (error) {
		console.error('Payment initialization failed:', error);
		return res.status(502).json({ message: 'Could not initialize payment.' });
	}
});

app.get('/health', (_req, res) => {
	res.json({ status: 'ok' });
});

app.listen(port, () => {
	console.log(`Payment backend listening on http://localhost:${port}`);
});
