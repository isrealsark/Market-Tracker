const path = require('path');
require('dotenv').config({
	path: path.join(__dirname, '.env'),
});

const express = require('express');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const helmet = require('helmet');
const {
	getCompanyStatus,
	registerCompany,
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
app.use(express.json({ limit: '10kb' }));

const plans = {
	monthly: { amount: 3000, currency: 'GHS' },
	yearly: { amount: 36000, currency: 'GHS' },
};

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
		await registerCompany({
			companyName: trimmedCompanyName,
			username: trimmedUsername,
		});
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

app.post('/api/payments/initialize', initializeLimiter, async (req, res) => {
	const {
		fullName,
		phone,
		email,
		plan = 'monthly',
		paymentMethod = 'Mobile Money',
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
		(trimmedEmail && !validEmail) ||
		!plans[plan] ||
		!['USSD', 'Card'].includes(paymentMethod)
	) {
		return res.status(400).json({
			message: 'Invalid customer, plan, payment method, or backend configuration.',
		});
	}

	const selectedPlan = plans[plan];
	const customerEmail = trimmedEmail || `customer-${Date.now()}@markettracker.app`;

	return res.status(501).json({
		message: 'USSD payment provider is not configured yet.',
		plan,
		amount: selectedPlan.amount,
		currency: selectedPlan.currency,
		customerEmail,
	});
});

app.get('/health', (_req, res) => {
	res.json({ status: 'ok' });
});

app.listen(port, () => {
	console.log(`Payment backend listening on http://localhost:${port}`);
});
