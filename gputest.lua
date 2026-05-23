-- gpu_test.lua
-- Diagnostic test for Tom's Peripherals GPU
-- Writes all output to gpu_test_log.txt

local log = {}
local function p(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end
    local line = table.concat(parts, "\t")
    log[#log + 1] = line
    print(line)
end

local function section(name)
    p("")
    p("=== " .. name .. " ===")
end

local function save()
    local f = io.open("gpu_test_log.txt", "w")
    for _, line in ipairs(log) do f:write(line .. "\n") end
    f:close()
    print(">> saved to gpu_test_log.txt")
end

-- ─── 1. Find GPU ──────────────────────────────────────────────────────────────

section("FIND GPU")
local gpu = peripheral.find("gpu")
if not gpu then
    p("no 'gpu' found, trying wrap('top')")
    gpu = peripheral.wrap("top")
end
assert(gpu, "No GPU found!")
p("GPU: " .. peripheral.getName(gpu))

-- ─── 2. GPU peripheral methods ────────────────────────────────────────────────

section("GPU PERIPHERAL METHODS")
for k, v in pairs(gpu) do p("  gpu." .. k .. " = " .. type(v)) end

-- ─── 3. refreshSize / setSize ─────────────────────────────────────────────────

section("refreshSize / setSize")
gpu.refreshSize(); p("refreshSize OK")
gpu.setSize(64);   p("setSize(64) OK")

-- ─── 4. gpu.getSize raw returns ───────────────────────────────────────────────

section("gpu.getSize() RAW")
local a,b,c,d,e = gpu.getSize()
p("r1="..tostring(a).." r2="..tostring(b).." r3="..tostring(c).." r4="..tostring(d).." r5="..tostring(e))

-- ─── 5. createWindow ──────────────────────────────────────────────────────────

section("createWindow")
local pw, ph = a, b
p("Using pw="..tostring(pw).." ph="..tostring(ph))
local ok, ctx = pcall(gpu.createWindow, 0, 0, pw, ph)
if not ok then
    p("FAIL createWindow(0,0): " .. tostring(ctx))
    p("Trying createWindow(1,1)...")
    ok, ctx = pcall(gpu.createWindow, 1, 1, pw, ph)
    if not ok then p("FAIL: "..tostring(ctx)); save(); return end
end
p("createWindow OK")

-- ─── 6. ctx methods ───────────────────────────────────────────────────────────

section("CTX METHODS")
for k, v in pairs(ctx) do p("  ctx." .. k .. " = " .. type(v)) end

-- ─── 7. ctx.getSize raw returns ───────────────────────────────────────────────

section("ctx.getSize() RAW")
local ca,cb,cc,cd = ctx.getSize()
p("r1="..tostring(ca).." r2="..tostring(cb).." r3="..tostring(cc).." r4="..tostring(cd))
local sw, sh = ca, cb
p("Using sw="..tostring(sw).." sh="..tostring(sh))

-- ─── 8. getTextLength ─────────────────────────────────────────────────────────

section("getTextLength")
local ok2, tlen = pcall(ctx.getTextLength, "Hello", 1)
if ok2 then p("getTextLength('Hello',1) = "..tostring(tlen))
else        p("FAIL: "..tostring(tlen)) end

-- ─── 9. filledRectangle origin tests ─────────────────────────────────────────
-- We know (0,0) crashes and (3,3) works — find the exact boundary

section("filledRectangle ORIGIN TESTS (finding min x/y)")

local function tryRect(label, x, y, w, h, color)
    local ok, err = pcall(ctx.filledRectangle, x, y, w, h, color)
    p((ok and "OK  " or "FAIL").." "..label.." rect("..x..","..y..","..w..","..h..")"
      ..(ok and "" or " => "..tostring(err)))
end

-- Scan origin x from 0..4 with a small safe rect
for x = 0, 4 do tryRect("x="..x..",y=1", x, 1, 10, 4, 0x333333) end
-- Scan origin y from 0..4
for y = 0, 4 do tryRect("x=1,y="..y, 1, y, 10, 4, 0x333333) end

-- ─── 10. filledRectangle right/bottom edge tests ──────────────────────────────

section("filledRectangle EDGE TESTS (finding max x/y)")

-- Try different widths from right edge
tryRect("w=sw",   1, 1, sw,   10, 0x111111)
tryRect("w=sw-1", 1, 1, sw-1, 10, 0x111111)
tryRect("w=sw-2", 1, 1, sw-2, 10, 0x111111)
tryRect("w=sw-3", 1, 1, sw-3, 10, 0x111111)

-- Try x offset + width
tryRect("x=1,w=sw-1", 1, 1, sw-1, 10, 0x111111)
tryRect("x=2,w=sw-2", 2, 1, sw-2, 10, 0x111111)
tryRect("x=3,w=sw-3", 3, 1, sw-3, 10, 0x111111)

-- ─── 11. drawText origin tests ────────────────────────────────────────────────

section("drawText ORIGIN TESTS")

local function tryText(label, x, y)
    local ok, err = pcall(ctx.drawText, x, y, "Hi", 0xFFFFFF, 0x000000, 1)
    p((ok and "OK  " or "FAIL").." "..label.." text("..x..","..y..")"
      ..(ok and "" or " => "..tostring(err)))
end

for x = 0, 4 do tryText("x="..x..",y=1", x, 1) end
for y = 0, 4 do tryText("x=1,y="..y, 1, y) end

-- ─── 12. sync ─────────────────────────────────────────────────────────────────

section("SYNC")
local ok3, e3 = pcall(ctx.sync); p("ctx.sync: "..(ok3 and "OK" or tostring(e3)))
local ok4, e4 = pcall(gpu.sync); p("gpu.sync: "..(ok4 and "OK" or tostring(e4)))

section("DONE")
save()