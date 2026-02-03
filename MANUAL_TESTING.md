# Manual Testing Guide for StandardInputReader and StandardOutputWriter

This guide provides manual testing procedures for the `StandardInputReader` and `StandardOutputWriter` implementations used in the stdio transport.

## Prerequisites

Build the MCPExample executable:
```bash
swift build
```

## Test 1: Basic Input/Output (Echo Test)

**Purpose**: Verify that `StandardInputReader` can read from stdin and `StandardOutputWriter` can write to stdout.

### Test Steps:

1. Run MCPExample in stdio mode:
```bash
swift run MCPExample stdio
```

2. Send an initialize request:
```bash
echo '{"jsonrpc":"2.0","id":"1","method":"initialize"}' | swift run MCPExample stdio
```

**Expected Output**: Should see a JSON response with server capabilities:
```json
{
  "id": "1",
  "jsonrpc": "2.0",
  "result": {
    "capabilities": {...},
    "protocolVersion": "2025-06-18",
    "serverInfo": {...}
  }
}
```

✅ **Pass Criteria**: 
- Response is valid JSON
- Contains "result" field
- No errors printed to stderr

---

## Test 2: Multiple Sequential Requests

**Purpose**: Verify the reader can handle multiple lines and writer outputs each response.

### Test Steps:

1. Create a test input file:
```bash
cat > test_input.txt << 'EOF'
{"jsonrpc":"2.0","id":"1","method":"initialize"}
{"jsonrpc":"2.0","id":"2","method":"tools/list"}
{"jsonrpc":"2.0","id":"3","method":"resources/list"}
EOF
```

2. Run with multiple inputs:
```bash
swift run MCPExample stdio < test_input.txt
```

**Expected Output**: Should see 3 JSON responses, one for each request:
```json
{"id":"1",...}
{"id":"2",...}
{"id":"3",...}
```

✅ **Pass Criteria**:
- Exactly 3 responses
- Each response has the correct ID (1, 2, 3)
- All responses are valid JSON

---

## Test 3: Interactive Mode (Manual Input)

**Purpose**: Verify reader works with interactive stdin (terminal input).

### Test Steps:

1. Run in interactive mode:
```bash
swift run MCPExample stdio
```

2. Type requests manually (press Enter after each):
```
{"jsonrpc":"2.0","id":"1","method":"tools/list"}
```

3. Observe response immediately after pressing Enter

4. Type another request:
```
{"jsonrpc":"2.0","id":"2","method":"resources/list"}
```

5. Press Ctrl+D (or Cmd+D on Mac) to send EOF

✅ **Pass Criteria**:
- Each response appears immediately after pressing Enter
- No buffering delays
- Clean exit after EOF

---

## Test 4: Large Input (Buffer Handling)

**Purpose**: Verify reader/writer handle longer JSON payloads.

### Test Steps:

1. Create a request with long strings:
```bash
cat > large_input.txt << 'EOF'
{"jsonrpc":"2.0","id":"1","method":"tools/call","params":{"name":"add_numbers","arguments":{"a":123456789.123456789,"b":987654321.987654321}}}
EOF
```

2. Run:
```bash
swift run MCPExample stdio < large_input.txt
```

**Expected Output**: Should see successful response with sum:
```json
{"id":"1","jsonrpc":"2.0","result":{"content":[{"text":"...1111111111.111111...","type":"text"}]}}
```

✅ **Pass Criteria**:
- Response contains correct calculation
- No truncation
- No buffer overflow errors

---

## Test 5: Malformed Input (Error Handling)

**Purpose**: Verify reader handles invalid JSON gracefully.

### Test Steps:

1. Send malformed JSON:
```bash
echo '{ invalid json }' | swift run MCPExample stdio
```

**Expected Output**: Should see a parse error response:
```json
{"error":{"code":-32700,"message":"Parse error: ..."},"jsonrpc":"2.0"}
```

✅ **Pass Criteria**:
- Returns error response (not crash)
- Error code is -32700 (parse error)
- Server continues running (for multi-line test)

---

## Test 6: Empty Input (EOF Handling)

**Purpose**: Verify reader returns nil on EOF and causes clean exit.

### Test Steps:

1. Send empty input:
```bash
echo -n "" | swift run MCPExample stdio
```

**Expected Output**: 
- No output (no requests processed)
- Clean exit (no errors)

✅ **Pass Criteria**:
- Exits immediately
- No error messages
- Exit code 0

---

## Test 7: Flush Behavior (Output Buffering)

**Purpose**: Verify writer flushes output after each response.

### Test Steps:

1. Run in background and monitor output in real-time:
```bash
(
  echo '{"jsonrpc":"2.0","id":"1","method":"tools/list"}' 
  sleep 1
  echo '{"jsonrpc":"2.0","id":"2","method":"resources/list"}'
  sleep 1
  echo '{"jsonrpc":"2.0","id":"3","method":"prompts/list"}'
) | swift run MCPExample stdio
```

**Expected Behavior**:
- First response appears immediately (not after all 3 requests)
- Each response appears as soon as its request is processed
- No waiting for buffer to fill

✅ **Pass Criteria**:
- Immediate output (no batching)
- Responses appear in order
- No delay between request and response

---

## Test 8: Unicode Support

**Purpose**: Verify reader/writer handle UTF-8 correctly.

### Test Steps:

1. Send request with unicode characters:
```bash
echo '{"jsonrpc":"2.0","id":"1","method":"prompts/get","params":{"name":"explain_math","arguments":{"concept":"π and ∑"}}}' | swift run MCPExample stdio
```

**Expected Output**: Response contains the unicode characters correctly:
```json
{"id":"1","jsonrpc":"2.0","result":{"messages":[{"content":{"text":"Please explain the mathematical concept: π and ∑",...}]}}
```

✅ **Pass Criteria**:
- Unicode characters preserved in output
- No encoding errors
- Valid JSON output

---

## Test 9: Newline Handling

**Purpose**: Verify reader uses line-based input (not character-based).

### Test Steps:

1. Create multi-line input with embedded newlines in strings:
```bash
cat > newline_test.txt << 'EOF'
{"jsonrpc":"2.0","id":"1","method":"prompts/get","params":{"name":"explain_math","arguments":{"concept":"line1"}}}
{"jsonrpc":"2.0","id":"2","method":"prompts/get","params":{"name":"explain_math","arguments":{"concept":"line2"}}}
EOF
```

2. Run:
```bash
swift run MCPExample stdio < newline_test.txt
```

✅ **Pass Criteria**:
- Two separate responses
- Each request processed as one line
- No partial line processing

---

## Test 10: Performance (Throughput)

**Purpose**: Verify reader/writer handle high volume.

### Test Steps:

1. Generate 1000 requests:
```bash
for i in {1..1000}; do
  echo "{\"jsonrpc\":\"2.0\",\"id\":\"$i\",\"method\":\"tools/list\"}"
done | swift run MCPExample stdio > output.txt
```

2. Verify output:
```bash
wc -l output.txt
# Should show 1000 lines
```

✅ **Pass Criteria**:
- All 1000 requests processed
- No dropped requests
- Reasonable performance (completes in < 5 seconds)
- No memory leaks (check Activity Monitor during test)

---

## Test Summary Template

After running all tests, use this template to document results:

```
## StandardInputReader / StandardOutputWriter Test Results

Date: ____________
Tester: ____________
Platform: macOS / Linux
Swift Version: ____________

| Test | Status | Notes |
|------|--------|-------|
| 1. Basic I/O | ☐ Pass ☐ Fail | |
| 2. Multiple Sequential | ☐ Pass ☐ Fail | |
| 3. Interactive Mode | ☐ Pass ☐ Fail | |
| 4. Large Input | ☐ Pass ☐ Fail | |
| 5. Malformed Input | ☐ Pass ☐ Fail | |
| 6. Empty Input | ☐ Pass ☐ Fail | |
| 7. Flush Behavior | ☐ Pass ☐ Fail | |
| 8. Unicode Support | ☐ Pass ☐ Fail | |
| 9. Newline Handling | ☐ Pass ☐ Fail | |
| 10. Performance | ☐ Pass ☐ Fail | |

**Overall Result**: ☐ All Pass ☐ Some Failures

**Issues Found**:
- 

**Additional Notes**:
- 
```

---

## Cleanup

Remove test files after testing:
```bash
rm -f test_input.txt large_input.txt newline_test.txt output.txt
```

---

## Quick Test Script

For convenience, here's a script that runs basic smoke tests:

```bash
#!/bin/bash
# smoke_test_stdio.sh

echo "🧪 Running stdio smoke tests..."
echo ""

# Test 1: Basic request
echo "Test 1: Basic initialize request"
echo '{"jsonrpc":"2.0","id":"1","method":"initialize"}' | swift run MCPExample stdio > /tmp/test1.txt
if grep -q "serverInfo" /tmp/test1.txt; then
  echo "✅ PASS"
else
  echo "❌ FAIL"
fi
echo ""

# Test 2: Tools list
echo "Test 2: Tools list"
echo '{"jsonrpc":"2.0","id":"2","method":"tools/list"}' | swift run MCPExample stdio > /tmp/test2.txt
if grep -q "add_numbers" /tmp/test2.txt; then
  echo "✅ PASS"
else
  echo "❌ FAIL"
fi
echo ""

# Test 3: Multiple requests
echo "Test 3: Multiple sequential requests"
(echo '{"jsonrpc":"2.0","id":"1","method":"tools/list"}'; echo '{"jsonrpc":"2.0","id":"2","method":"resources/list"}') | swift run MCPExample stdio > /tmp/test3.txt
if [ $(wc -l < /tmp/test3.txt) -eq 2 ]; then
  echo "✅ PASS"
else
  echo "❌ FAIL"
fi
echo ""

# Test 4: Error handling
echo "Test 4: Malformed JSON"
echo '{ bad json }' | swift run MCPExample stdio > /tmp/test4.txt
if grep -q "Parse error" /tmp/test4.txt; then
  echo "✅ PASS"
else
  echo "❌ FAIL"
fi
echo ""

# Cleanup
rm -f /tmp/test*.txt

echo "🎉 Smoke tests complete!"
```

Save as `smoke_test_stdio.sh`, make executable (`chmod +x smoke_test_stdio.sh`), and run:
```bash
./smoke_test_stdio.sh
```
