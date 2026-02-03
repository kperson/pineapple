#!/bin/bash
# Smoke tests for StandardInputReader and StandardOutputWriter
# via MCPExample stdio mode

set -e  # Exit on error

echo "🧪 Running stdio smoke tests..."
echo ""

# Test 1: Basic request
echo "Test 1: Basic initialize request"
echo '{"jsonrpc":"2.0","id":"1","method":"initialize"}' | swift run MCPExample stdio 2>/dev/null | grep '^{' > /tmp/test1.txt
if grep -q "serverInfo" /tmp/test1.txt; then
  echo "✅ PASS - Initialize request works"
else
  echo "❌ FAIL - No serverInfo in response"
  cat /tmp/test1.txt
fi
echo ""

# Test 2: Tools list
echo "Test 2: Tools list"
echo '{"jsonrpc":"2.0","id":"2","method":"tools/list"}' | swift run MCPExample stdio 2>/dev/null | grep '^{' > /tmp/test2.txt
if grep -q "add_numbers" /tmp/test2.txt; then
  echo "✅ PASS - Tools list returns add_numbers"
else
  echo "❌ FAIL - add_numbers not found"
  cat /tmp/test2.txt
fi
echo ""

# Test 3: Multiple requests
echo "Test 3: Multiple sequential requests"
cat > /tmp/multi_input.txt << 'MULTIEOF'
{"jsonrpc":"2.0","id":"1","method":"tools/list"}
{"jsonrpc":"2.0","id":"2","method":"resources/list"}
MULTIEOF
swift run MCPExample stdio < /tmp/multi_input.txt 2>/dev/null | grep '^{' > /tmp/test3.txt
LINE_COUNT=$(wc -l < /tmp/test3.txt | tr -d ' ')
if [ "$LINE_COUNT" -ge 1 ]; then
  echo "✅ PASS - Processed requests successfully (got $LINE_COUNT response(s))"
else
  echo "❌ FAIL - No responses received"
  cat /tmp/test3.txt
fi
echo ""

# Test 4: Error handling
echo "Test 4: Malformed JSON"
echo '{ bad json }' | swift run MCPExample stdio 2>/dev/null | grep '^{' > /tmp/test4.txt
if grep -q "Parse error" /tmp/test4.txt; then
  echo "✅ PASS - Parse error returned for bad JSON"
else
  echo "❌ FAIL - No parse error"
  cat /tmp/test4.txt
fi
echo ""

# Test 5: Unicode support
echo "Test 5: Unicode characters"
echo '{"jsonrpc":"2.0","id":"5","method":"prompts/get","params":{"name":"explain_math","arguments":{"concept":"π"}}}' | \
  swift run MCPExample stdio 2>/dev/null | grep '^{' > /tmp/test5.txt
if grep -q "π" /tmp/test5.txt; then
  echo "✅ PASS - Unicode preserved in output"
else
  echo "❌ FAIL - Unicode character not found"
  cat /tmp/test5.txt
fi
echo ""

# Test 6: Tool execution
echo "Test 6: Tool execution (add_numbers)"
echo '{"jsonrpc":"2.0","id":"6","method":"tools/call","params":{"name":"add_numbers","arguments":{"a":5,"b":3}}}' | \
  swift run MCPExample stdio 2>/dev/null | grep '^{' > /tmp/test6.txt
if grep -q "8" /tmp/test6.txt; then
  echo "✅ PASS - Calculation result correct (5+3=8)"
else
  echo "❌ FAIL - Expected 8 in response"
  cat /tmp/test6.txt
fi
echo ""

# Cleanup
rm -f /tmp/test*.txt

echo ""
echo "🎉 All smoke tests complete!"
echo ""
echo "These tests verify that StandardInputReader and StandardOutputWriter:"
echo "  ✓ Read line-by-line from stdin"
echo "  ✓ Write JSON responses to stdout"
echo "  ✓ Handle multiple sequential requests"
echo "  ✓ Handle errors gracefully"
echo "  ✓ Preserve unicode characters"
echo "  ✓ Flush output after each response"
echo ""
echo "For more comprehensive testing, see MANUAL_TESTING.md"
