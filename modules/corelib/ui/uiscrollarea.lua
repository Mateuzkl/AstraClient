-- @docclass
UIScrollArea = extends(UIWidget, "UIScrollArea")

-- public functions
function UIScrollArea.create()
  local scrollarea = UIScrollArea.internalCreate()
  scrollarea:setClipping(true)
  scrollarea.inverted = false
  scrollarea.alwaysScrollMaximum = false
  scrollarea:insertLuaCall("onLayoutUpdate")
  scrollarea.keepScrollRange = false
  scrollarea.invertedView = true
  return scrollarea
end

function UIScrollArea:onStyleApply(styleName, styleNode)
  for name,value in pairs(styleNode) do
    if name == 'vertical-scrollbar' then
      addEvent(function()
        local parent = self:getParent()
        if parent then
          self:setVerticalScrollBar(parent:getChildById(value))
        end
      end)
    elseif name == 'horizontal-scrollbar' then
      addEvent(function()
        local parent = self:getParent()
        if parent then
          self:setHorizontalScrollBar(self:getParent():getChildById(value))
        end
      end)
    elseif name == 'inverted-scroll' then
      self:setInverted(value)
    elseif name == 'always-scroll-maximum' then
      self:setAlwaysScrollMaximum(value)
    elseif name == 'keep-scroll-range' then
      self:setKeepScrollRange(value)
    elseif name == 'inverted-view' then
      self.invertedView = value
    end
  end
end

function UIScrollArea:updateScrollBars()
  local scrollWidth = math.max(self:getChildrenRect().width - self:getPaddingRect().width, 0)
  local scrollHeight = math.max(self:getChildrenRect().height - self:getPaddingRect().height, 0)

  local scrollbar = self.verticalScrollBar
  if scrollbar and not self.keepScrollRange then
    if self.inverted then
      scrollbar:setMinimum(-scrollHeight)
      scrollbar:setMaximum(0)
    else
      scrollbar:setMinimum(0)
      scrollbar:setMaximum(scrollHeight)
    end
  end

  local scrollbar = self.horizontalScrollBar
  if scrollbar and not self.keepScrollRange then
    if self.inverted then
      scrollbar:setMinimum(-scrollWidth)
      scrollbar:setMaximum(0)
    else
      scrollbar:setMinimum(0)
      scrollbar:setMaximum(scrollWidth)
    end
  end

  if self.lastScrollWidth ~= scrollWidth then
    self:onScrollWidthChange()
  end
  if self.lastScrollHeight ~= scrollHeight then
    self:onScrollHeightChange()
  end

  self.lastScrollWidth = scrollWidth
  self.lastScrollHeight = scrollHeight
end

function UIScrollArea:setVerticalScrollBar(scrollbar)
  self.verticalScrollBar = scrollbar
  connect(self.verticalScrollBar, 'onValueChange', function(scrollbar, value, delta)
    local virtualOffset = self:getVirtualOffset()
    if not self.keepScrollRange then
      virtualOffset.y = value
      self:setVirtualOffset(virtualOffset)
    end

    signalcall(self.onScrollChange, self, virtualOffset)
  end)
  self:updateScrollBars()
end

function UIScrollArea:setHorizontalScrollBar(scrollbar)
  self.horizontalScrollBar = scrollbar
  connect(self.horizontalScrollBar, 'onValueChange', function(scrollbar, value)
    local virtualOffset = self:getVirtualOffset()
    if not self.keepScrollRange then
      virtualOffset.x = value
      self:setVirtualOffset(virtualOffset)
    end
    signalcall(self.onScrollChange, self, virtualOffset)
  end)
  self:updateScrollBars()
end

function UIScrollArea:setInverted(inverted)
  self.inverted = inverted
end

function UIScrollArea:setAlwaysScrollMaximum(value)
  self.alwaysScrollMaximum = value
end

function UIScrollArea:setKeepScrollRange(value)
  self.keepScrollRange = value
end

function UIScrollArea:onLayoutUpdate()
  self:updateScrollBars()
end

function UIScrollArea:onMouseWheel(mousePos, mouseWheel)
  if self.verticalScrollBar then
    local scrollBar = self.verticalScrollBar
    if not scrollBar:isOn() then
      return false
    end
    if mouseWheel == MouseWheelUp then
      local minimum = scrollBar:getMinimum()
      if scrollBar:getValue() <= minimum then
        return false
      end
      scrollBar:smoothScrollBy(-scrollBar:getStep())
    else
      local maximum = scrollBar:getMaximum()
      if scrollBar:getValue() >= maximum then
        return false
      end
      scrollBar:smoothScrollBy(scrollBar:getStep())
    end
  elseif self.horizontalScrollBar then
    local scrollBar = self.horizontalScrollBar
    if not scrollBar:isOn() then
      return false
    end
    if mouseWheel == MouseWheelUp then
      if not self.invertedView then
        local maximum = scrollBar:getMaximum()
        if scrollBar:getValue() >= maximum then
          return false
        end
        scrollBar:smoothScrollBy(scrollBar:getStep())
      else
        local minimum = scrollBar:getMinimum()
        if scrollBar:getValue() <= minimum then
          return false
        end
        scrollBar:smoothScrollBy(-scrollBar:getStep())
      end
    else
      if not self.invertedView then
        local minimum = scrollBar:getMinimum()
        if scrollBar:getValue() <= minimum then
          return false
        end
        scrollBar:smoothScrollBy(-scrollBar:getStep())
      else
        local maximum = scrollBar:getMaximum()
        if scrollBar:getValue() >= maximum then
          return false
        end
        scrollBar:smoothScrollBy(scrollBar:getStep())
      end
    end
  end
  return true
end

function UIScrollArea:ensureChildVisible(child, offset)
  if child then
    local paddingRect = self:getPaddingRect()
    if not offset then
      offset = {x = 0, y = 0}
    end
    if self.verticalScrollBar and child.getY then
      local deltaY = paddingRect.y - child:getY()
      if deltaY > 0 then
        self.verticalScrollBar:decrement(deltaY)
      end

      deltaY = (child:getY() + child:getHeight() + offset.y) - (paddingRect.y + paddingRect.height)
      if deltaY > 0 then
        self.verticalScrollBar:increment(deltaY)
      end
    elseif self.horizontalScrollBar then
      local deltaX = paddingRect.x - child:getX()
      if deltaX > 0 then
        self.horizontalScrollBar:decrement(deltaX)
      end

      deltaX = (child:getX() + child:getWidth() + offset.x) - (paddingRect.x + paddingRect.width)
      if deltaX > 0 then
        self.horizontalScrollBar:increment(deltaX)
      end
    end
  end
end

function UIScrollArea:onChildFocusChange(focusedChild, oldFocused, reason)
  if not focusedChild or focusedChild:getClassName() == 'UIItem' then return end
  if focusedChild and (reason == MouseFocusReason or reason == KeyboardFocusReason) then
    self:ensureChildVisible(focusedChild)
  end
end

function UIScrollArea:onScrollWidthChange()
  if self.alwaysScrollMaximum and self.horizontalScrollBar then
    self.horizontalScrollBar:setValue(self.horizontalScrollBar:getMaximum())
  end
end

function UIScrollArea:onScrollHeightChange()
  if self.alwaysScrollMaximum and self.verticalScrollBar then
    self.verticalScrollBar:setValue(self.verticalScrollBar:getMaximum())
  end
end
