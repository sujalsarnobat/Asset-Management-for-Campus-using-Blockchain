# CampusChain — Deployment Package

## Files in This Package

| File | Purpose |
|------|---------|
| `CampusAssetBooking.sol` | Solidity smart contract (Solidity ^0.8.19) |
| `campus-booking-dapp.html` | Full frontend DApp (open in any browser) |
| `README.md` | This file — deployment instructions |

---

## Quick Deploy to Ganache

### Prerequisites
```bash
npm install -g ganache truffle
# Install MetaMask extension in Chrome/Firefox
```

### 1. Start Ganache (deterministic mode)
```bash
ganache --server.port 8545 --chain.chainId 1337 --chain.networkId 1337 --wallet.deterministic --wallet.totalAccounts 10
```
This gives 10 accounts with 100 ETH each. **Note the first 4 addresses and private keys.**

### 2. Create Truffle Project
```bash
mkdir campus-chain && cd campus-chain
truffle init
```

### 3. Place the Contract
Copy `CampusAssetBooking.sol` to `contracts/CampusAssetBooking.sol`.

### 4. Create Migration File
Create `migrations/2_deploy_campus.js`:
```javascript
const CampusAssetBooking = artifacts.require("CampusAssetBooking");
module.exports = function(deployer) {
  deployer.deploy(CampusAssetBooking);
};
```

### 5. Configure Truffle
Edit `truffle-config.js`:
```javascript
module.exports = {
  networks: {
    development: {
      host: "127.0.0.1",
      port: 8545,
      network_id: "1337",
    },
  },
  compilers: {
    solc: { version: "0.8.19" }
  }
};
```

### 6. Deploy
```bash
truffle migrate --network development
# Note the contract address from output
```

### 7. Get ABI
```bash
cat build/contracts/CampusAssetBooking.json | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['abi']))"
```

### 8. Configure MetaMask
- Add Network: RPC `http://127.0.0.1:8545`, Chain ID `1337`, Currency `ETH`
- Import 4 accounts using their private keys from Ganache output

### 9. Open the DApp
Open `campus-booking-dapp.html` in your browser:
- Go to **Setup Guide** tab
- Paste the **Contract Address**
- Paste the **ABI** and click "Load ABI"
- Click **Connect MetaMask**

---

## Testing Scenarios (4 Wallets)

### Wallet Roles
| Account | Role | Expected Behavior |
|---------|------|-------------------|
| Account 0 | Admin | Can register assets, users, cancel any booking |
| Account 1 | Registered User A | Can browse and book |
| Account 2 | Registered User B | Can browse and book |
| Account 3 | Unregistered | All booking attempts rejected at contract level |

### Test Sequence

#### A. Admin Setup (Account 0)
1. Connect → Admin Panel
2. Register 3–4 assets with different hourly fees
3. Register Account 1 and Account 2 as users
4. Do NOT register Account 3

#### B. Access Control Test (Account 3)
1. Switch MetaMask → Account 3
2. Try booking any asset
3. **Expected:** Contract reverts with "wallet not registered"

#### C. Normal Booking (Account 1)
1. Switch → Account 1
2. Book Seminar Hall, 2 hours, tomorrow 10:00–12:00
3. MetaMask popup → approve exact ETH
4. **Expected:** Booking confirmed, slot marked occupied

#### D. Conflict Detection (Account 2)
1. Switch → Account 2
2. Attempt to book same asset, overlapping time (e.g. 11:00–13:00)
3. **Expected:** Contract rejects — "slot conflict" — ETH returned
4. Book non-overlapping slot (13:00–15:00) — should succeed

#### E. Tiered Refund — 100% (Account 1)
1. Book a slot more than 24 hours in the future
2. Immediately cancel from My Bookings
3. **Expected:** Full ETH refunded

#### F. Tiered Refund — 50% (Account 2)
1. Book a slot within 24 hours from now
2. Cancel from My Bookings
3. **Expected:** 50% ETH refunded, 50% stays in contract as penalty

#### G. Admin Cancel — 100% (Account 0)
1. Switch → Admin
2. Admin Panel → load all bookings → cancel any active booking
3. **Expected:** 100% ETH refunded regardless of timing

#### H. Penalty Withdrawal (Account 0)
1. Admin Panel → Check Balance → shows accumulated 50% penalties
2. Click Withdraw → ETH transferred to admin wallet

---

## Smart Contract Architecture

```
CampusAssetBooking
├── Access Control
│   ├── admin (owner, set at deployment)
│   ├── registeredUsers mapping (whitelist)
│   ├── registerUser() / registerUsers() — admin only
│   └── removeUser() — admin only
│
├── Asset Management
│   ├── assets mapping (id → Asset struct)
│   ├── registerAsset() — admin only
│   ├── updateAsset() — admin only
│   └── deactivateAsset() — admin only (soft delete)
│
├── Booking Engine
│   ├── bookAsset() — registered users only, payable
│   │   ├── validates future timestamps
│   │   ├── validates whole-hour duration
│   │   ├── validates exact ETH payment
│   │   └── O(n) conflict scan → revert on overlap
│   └── bookings mapping (id → Booking struct)
│
└── Cancellation & Refunds
    ├── adminCancelBooking() — 100% refund, any booking
    ├── userCancelBooking() — tiered refund
    │   ├── > 24h before slot → 100% refund
    │   └── ≤ 24h before slot → 50% refund
    └── withdrawPenalties() — admin collects 50% penalties
```

## Key Security Properties
- **No double booking:** Conflict check in O(n) before recording booking
- **Exact payment:** msg.value must equal fee × hours exactly
- **No re-entrancy:** State updated before ETH transfer
- **Immutable history:** Cancelled bookings remain on-chain with full audit trail
- **Block timestamp:** All time comparisons use block.timestamp (Ganache-safe)
# Asset-Management-for-Campus-using-Blockchain
