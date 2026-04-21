#!/bin/sh
set -e

echo "⏳ Waiting for Ganache at $GANACHE_HOST:$GANACHE_PORT..."
until nc -z "$GANACHE_HOST" "$GANACHE_PORT"; do
  sleep 1
done

echo "✅ Ganache is up!"

echo "🔨 Compiling contract..."
truffle compile

echo "🚀 Deploying contract..."
truffle migrate --network development

echo ""
echo "═══════════════════════════════════════════════════════"
echo "✅  DEPLOYMENT COMPLETE"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "📋 Contract Address:"
node -e "
  const data = require('./build/contracts/CampusAssetBooking.json');
  const netId = Object.keys(data.networks)[0];
  console.log('  👉 ' + data.networks[netId].address);
"

echo ""
echo "📋 ABI saved to: build/contracts/CampusAssetBooking.json"
echo ""
echo "🔑 Deterministic Ganache Accounts (first 4):"
echo "  Account 0 (Admin):        0x627306090abaB3A6e1400e9345bC60c78a8BEf57"
echo "  Account 1 (User A):       0xf17f52151EbEF6C7334FAD080c5704D77216b732"
echo "  Account 2 (User B):       0xC5fdf4076b8F3A5357c5E395ab970B5B54098Fef"
echo "  Account 3 (Unregistered): 0x821aEa9a577a9b44299B9c15c88cf3087F3b5544"
echo ""
echo "🔑 Private Keys (import into MetaMask):"
echo "  Account 0: 0xc87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3"
echo "  Account 1: 0xae6ae8e5ccbfb04590405997ee2d52d2b330726137b875053c36d94e974d162f"
echo "  Account 2: 0x0dbbe8e4ae425a6d2687f1a7e3ba17bc98c673636790f1b8ad91193c05875ef1"
echo "  Account 3: 0xc88b703fb08cbea894b6aeff5a544fb92e78a18e19814cd85da83b71f772aa6c"
echo ""
echo "🌐 Open the DApp at: http://localhost:3000"
echo "   MetaMask Network: http://127.0.0.1:8545  |  Chain ID: 1337"
echo "═══════════════════════════════════════════════════════"
