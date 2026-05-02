-- CreateIndex (only if column exists)
CREATE INDEX IF NOT EXISTS "Transaction_flutterwaveRef_idx" ON "Transaction"("flutterwaveRef");
CREATE INDEX IF NOT EXISTS "User_virtualAccountNumber_idx" ON "User"("virtualAccountNumber");