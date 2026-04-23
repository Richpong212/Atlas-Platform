import express from "express";

const app = express();
const port = Number(process.env.PORT) || 3303;
const authServiceUrl =
  process.env.AUTH_SERVICE_URL || "http://atlas-auth-service";

app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

app.get("/version", (_req, res) => {
  res.json({
    service: "atlas-api",
    version: "1.0.0",
    env: process.env.NODE_ENV || "dev",
  });
});

app.get("/auth-check", async (_req, res) => {
  try {
    const response = await fetch(`${authServiceUrl}/validate`);
    const data = await response.json();
    res.json({
      api: "atlas-api",
      auth: data,
    });
  } catch (error) {
    res.status(500).json({
      error: "Failed to reach auth-service",
    });
  }
});

app.listen(port, "0.0.0.0", () => {
  console.log(`Server running on port ${port}`);
});
