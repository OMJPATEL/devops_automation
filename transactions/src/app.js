const express = require('express');
const { MongoClient, ObjectId } = require('mongodb');

const app = express();
app.use(express.json());

// Environment
const PORT = Number(process.env.PORT || 3000);
const MONGO_URI = process.env.MONGO_URI || "mongodb://mongo:27017/bank_app";

console.log("Starting transactions service...");
console.log("MongoDB URI:", MONGO_URI);

// Logging middleware
app.use((req, _res, next) => {
  console.log(`${new Date().toISOString()} - ${req.method} ${req.url}`);
  next();
});

// Database connection
let db;

(async () => {
  try {
    const client = await MongoClient.connect(MONGO_URI);
    db = client.db("bank_app");   // always correct DB
    console.log("Connected to MongoDB.");
  } catch (err) {
    console.error("MongoDB connection failed:", err);
    process.exit(1);
  }
})();

// Util
const isValidObjectId = (id) => /^[a-fA-F0-9]{24}$/.test(id || "");

// Normalizes embedded date
const normalizeDateStage = {
  $addFields: {
    "transactions.date": {
      $cond: [
        { $eq: [{ $type: "$transactions.date" }, "string"] },
        { $toDate: "$transactions.date" },
        "$transactions.date"
      ]
    }
  }
};

// Group structure for results
const groupByMonthStage = {
  $group: {
    _id: {
      year: { $year: "$transactions.date" },
      month: { $month: "$transactions.date" }
    },
    count: { $sum: 1 },
    totalAmount: { $sum: "$transactions.amount" },
    items: {
      $push: {
        type: "$transactions.type",
        amount: "$transactions.amount",
        date: "$transactions.date"
      }
    }
  }
};

const sortDescStage = { $sort: { "_id.year": -1, "_id.month": -1 } };

// Health check
app.get("/status", (_req, res) => {
  res.json({ ok: true });
});

// Get all transactions for all users
app.get("/list", async (_req, res) => {
  try {
    if (!db) return res.status(503).json({ error: "Database not ready" });

    const pipeline = [
      { $match: { transactions: { $exists: true, $ne: [] } } },
      { $unwind: "$transactions" },
      normalizeDateStage,
      groupByMonthStage,
      sortDescStage
    ];

    const data = await db.collection("users").aggregate(pipeline).toArray();
    res.json(data);

  } catch (err) {
    console.error("Error fetching list:", err);
    res.status(500).json({ error: "Unable to load transactions" });
  }
});

// Get transactions for a specific user
app.get("/:userId", async (req, res) => {
  try {
    if (!db) return res.status(503).json({ error: "Database not ready" });

    const { userId } = req.params;

    if (!isValidObjectId(userId)) {
      return res.status(400).json({ error: "Invalid user id" });
    }

    const userObjectId = new ObjectId(userId);

    const user = await db
      .collection("users")
      .findOne({ _id: userObjectId }, { projection: { _id: 1 } });

    if (!user) return res.status(404).json({ error: "User not found" });

    const pipeline = [
      { $match: { _id: userObjectId, transactions: { $exists: true, $ne: [] } } },
      { $unwind: "$transactions" },
      normalizeDateStage,
      groupByMonthStage,
      sortDescStage
    ];

    const data = await db.collection("users").aggregate(pipeline).toArray();
    res.json(data);

  } catch (err) {
    console.error("Error fetching user transactions:", err);
    res.status(500).json({ error: "Unable to load user transactions" });
  }
});

// Start server
app.listen(PORT, "0.0.0.0", () => {
  console.log(`Transactions service running on port ${PORT}`);
});
