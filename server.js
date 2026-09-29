require("dotenv").config();
const express = require("express");
const app = express();

// The webhook MUST be registered before express.json(),
// otherwise the body is already parsed and the signature check fails.
app.use(require("./routes/webhook"));

app.use(express.json());

// ...your other routes go here

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Running on port ${PORT}`));
