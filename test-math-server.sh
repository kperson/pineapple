#!/bin/bash
# Quick test script for SimpleMathServer via MCPExample

BASE_URL="http://localhost:8080/math"

echo "🧮 Testing SimpleMathServer HTTP Interface"
echo ""

echo "1️⃣  Testing initialize..."
curl -s -X POST $BASE_URL \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "method": "initialize", "id": 1}' | jq .
echo ""

echo "2️⃣  Testing tools/list..."
curl -s -X POST $BASE_URL \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "method": "tools/list", "id": 2}' | jq .
echo ""

echo "3️⃣  Testing add_numbers tool (5 + 3)..."
curl -s -X POST $BASE_URL \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "method": "tools/call", "params": {"name": "add_numbers", "arguments": {"a": 5, "b": 3}}, "id": 3}' | jq .
echo ""

echo "4️⃣  Testing resources/list..."
curl -s -X POST $BASE_URL \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "method": "resources/list", "id": 4}' | jq .
echo ""

echo "5️⃣  Testing resources/read (pi constant)..."
curl -s -X POST $BASE_URL \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "method": "resources/read", "params": {"uri": "math://constants/pi"}, "id": 5}' | jq .
echo ""

echo "6️⃣  Testing prompts/list..."
curl -s -X POST $BASE_URL \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "method": "prompts/list", "id": 6}' | jq .
echo ""

echo "7️⃣  Testing prompts/get (explain_math)..."
curl -s -X POST $BASE_URL \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "method": "prompts/get", "params": {"name": "explain_math", "arguments": {"concept": "derivatives"}}, "id": 7}' | jq .
echo ""

echo "✅ All tests complete!"
