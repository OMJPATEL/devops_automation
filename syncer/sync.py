#!/usr/bin/env python3
import os
import time
import hashlib
from pymongo import MongoClient, ReplaceOne
from datetime import datetime

SRC_URI = os.environ.get("SRC_URI", "mongodb://mongo-backend:27017")
SRC_DB  = os.environ.get("SRC_DB",  "bank_app")
DEST_URI = os.environ.get("DEST_URI", "mongodb://mongo-transactions:27017")
DEST_DB  = os.environ.get("DEST_DB",  "transactions_db")
INTERVAL = int(os.environ.get("INTERVAL_SECONDS", "300"))

def make_txn_docs(user):
    user_id = str(user.get("_id"))
    txs = user.get("transactions", []) or []
    docs = []
    for t in txs:
        # deterministic id by hashing contents + user id
        h = hashlib.sha1((user_id + str(t)).encode("utf-8")).hexdigest()
        doc = {
            "_id": h,
            "user_id": user_id,
            "type": t.get("type"),
            "amount": t.get("amount"),
            "timestamp": t.get("timestamp") or t.get("time") or datetime.utcnow().isoformat(),
            "balance_after": t.get("balance_after")
        }
        docs.append(doc)
    return docs

def sync_once(src, dst):
    s_users = src["users"]
    d_tx = dst["transactions"]
    ops = []
    for user in s_users.find({}, {"transactions": 1}):
        for doc in make_txn_docs(user):
            ops.append(ReplaceOne({"_id": doc["_id"]}, doc, upsert=True))
        if len(ops) >= 500:
            d_tx.bulk_write(ops, ordered=False)
            ops = []
    if ops:
        d_tx.bulk_write(ops, ordered=False)

if __name__ == "__main__":
    src_client = MongoClient(SRC_URI)[SRC_DB]
    dst_client = MongoClient(DEST_URI)[DEST_DB]
    print(f"[syncer] Starting sync loop {SRC_URI}/{SRC_DB} -> {DEST_URI}/{DEST_DB} every {INTERVAL}s")
    while True:
        try:
            sync_once(src_client, dst_client)
            print(f"[syncer] Sync complete at {datetime.utcnow().isoformat()}Z")
        except Exception as e:
            print(f"[syncer] ERROR: {e}")
        time.sleep(INTERVAL)
