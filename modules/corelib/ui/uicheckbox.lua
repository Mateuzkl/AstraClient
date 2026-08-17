-- @docclass
UICheckBox = extends(UIWidget, "UICheckBox")

function UICheckBox.create()
  local checkbox = UICheckBox.internalCreate()
  checkbox:setFocusable(false)
  checkbox:setTextAlign(AlignLeft)
  checkbox:insertLuaCall("onEnabledChange")
  return checkbox
end

function UICheckBox:onClick(mousePos)
  self:setChecked(not self:isChecked())
  if not self:isDestroyed() then
    self:dispatchLeftClick(mousePos)
  end
end

function UICheckBox:onEnabledChange(checked)
  if not checked and self:isChecked() then
    self:setImageClip("0 24 12 12")
  end
end
