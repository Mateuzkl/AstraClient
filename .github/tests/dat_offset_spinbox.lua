local spinBoxScript = assert(arg[1], 'missing uispinbox.lua path')

UITextEdit = {}
extends = function()
  return {}
end
signalcall = function(callback, self, value)
  callback(self, value)
end
table.empty = function(value)
  return next(value) == nil
end

assert(loadfile(spinBoxScript))()

local displayed = '0'
local spinBox = setmetatable({
  value = 0,
  minimum = -32768,
  maximum = 32767,
  step = 1,
  allowModifiers = false,
  possibleValues = {}
}, { __index = UISpinBox })

function spinBox:getText()
  return displayed
end

function spinBox:setText(value)
  displayed = tostring(value)
end

function spinBox:getChildById()
  return nil
end

spinBox:setValue(8, true)
assert(spinBox:getValue() == 8 and spinBox:getText() == '8')
spinBox:up()
assert(spinBox:getValue() == 9 and spinBox:getText() == '9')

spinBox:setValue(-8, true)
assert(spinBox:getValue() == -8 and spinBox:getText() == '-8')
spinBox:down()
assert(spinBox:getValue() == -9 and spinBox:getText() == '-9')

print('DAT offset spinboxes: OK')
