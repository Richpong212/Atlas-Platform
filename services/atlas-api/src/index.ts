import express, { Request, Response } from "express";

const app = express();
const port = Number(process.env.PORT || 3000);
const nodeEnv = process.env.NODE_ENV || "development";
const appVersion = process.env.APP_VERSION || "v1";

app.use(express.json());

app.get("/health", (_req: Request, res: Response) => {
  res.status(200).json({
    status: "ok",
    service: "atlas-api",
  });
});

app.get("/ready", (_req: Request, res: Response) => {
  res.status(200).json({
    status: "ready",
    service: "atlas-api",
  });
});

app.get("/version", (_req: Request, res: Response) => {
  res.status(200).json({
    service: "atlas-api",
    version: appVersion,
    environment: nodeEnv,
  });
});

app.get("/", (_req: Request, res: Response) => {
  res.status(200).json({
    message: "Atlas API is running",
  });
});

app.listen(port, "0.0.0.0", () => {
  console.log(`atlas-api listening on port ${port}`);
});
