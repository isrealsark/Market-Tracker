const express = require("express");
const crypto = require("crypto");
const { markCompanyPaid } = require("../services/companyDatabase");
const router = express.Router();

// The variable_name of the "Company name" field on your Paystack payment page.
// Make one test payment and log event.data to confirm the exact value.
const COMPANY_FIELD = "company_name";

// ---------------------------------------------------------------
// THE ONE FUNCTION YOU NEED TO FILL IN
// Mark the company as paid and return how many companies were
// updated (0 means no company matched that name).
// ---------------------------------------------------------------
router.post(
  "/paystack/webhook",
  express.raw({ type: "application/json" }), // raw body is needed for the signature check
  async (req, res) => {
    if (!process.env.PAYSTACK_SECRET_KEY) return res.sendStatus(500);

    // 1. Verify the request really came from Paystack
    const expected = crypto
      .createHmac("sha512", process.env.PAYSTACK_SECRET_KEY)
      .update(req.body)
      .digest("hex");

    const received = req.headers["x-paystack-signature"] || "";
    const valid =
      expected.length === received.length &&
      crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(received));

    if (!valid) return res.sendStatus(401);

    const event = JSON.parse(req.body.toString());

    try {
      // 2. Only act on successful payments
      if (event.event === "charge.success") {
        const amount = Number(event.data.amount);
        if (
          event.data.currency !== "GHS" ||
          ![3000, 36000].includes(amount)
        ) {
          console.warn("Ignored payment with unexpected amount or currency");
          return res.sendStatus(200);
        }

        // Uncomment once to see exactly what Paystack sends:
        // console.log(JSON.stringify(event.data, null, 2));

        // 3. Read the company name the payer typed on the Paystack page
        const fields = event.data.metadata?.custom_fields || [];
        const field = fields.find((f) => f.variable_name === COMPANY_FIELD);
        const companyName = (field?.value || "").trim().toLowerCase();

        // 4. Mark that company as paid
        if (companyName) {
          const updated = await markCompanyPaid(companyName, event.data);
          if (!updated) {
            console.warn("Payment received but no company matched:", companyName);
          }
        } else {
          console.warn("Payment received with no company name:", event.data.reference);
        }
      }

      // 5. Tell Paystack we got it
      return res.sendStatus(200);
    } catch (err) {
      // A 500 makes Paystack retry the webhook later
      console.error("Webhook error:", err);
      return res.sendStatus(500);
    }
  }
);

module.exports = router;
