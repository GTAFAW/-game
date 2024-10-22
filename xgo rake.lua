if RakeScriptLoaded then return end;
getgenv().RakeScriptLoaded = true;

-- Services:
local Players = game:GetService("Players");
local Workspace = game:GetService("Workspace");
local ReplicatedStorage = game:GetService("ReplicatedStorage");
local PathfindingService = game:GetService("PathfindingService");
local ContextActionService = game:GetService("ContextActionService");
local RunService = game:GetService("RunService");

-- Libraries:
local Janitor; do -- Janitor
    local IndicesReference = newproxy(true)
    getmetatable(IndicesReference).__tostring = function()
        return "IndicesReference"
    end

    local LinkToInstanceIndex = newproxy(true)
    getmetatable(LinkToInstanceIndex).__tostring = function()
        return "LinkToInstanceIndex"
    end

    local METHOD_NOT_FOUND_ERROR = "Object %s doesn't have method %s, are you sure you want to add it? Traceback: %s"

    local janitor = {
        ClassName = "Janitor";
        __index = {
            CurrentlyCleaning = true;
            [IndicesReference] = nil;
        };
    }

    local TypeDefaults = {
        ["function"] = true;
        RBXScriptConnection = "Disconnect";
    }

    function janitor.new()
        return setmetatable({
            CurrentlyCleaning = false;
            [IndicesReference] = nil;
        }, janitor)
    end

    function janitor.Is(Object)
        return type(Object) == "table" and getmetatable(Object) == janitor
    end

    function janitor.__index:Add(Object, MethodName, Index)
        if Index then
            self:Remove(Index)

            local This = self[IndicesReference]
            if not This then
                This = {}
                self[IndicesReference] = This
            end

            This[Index] = Object
        end

        MethodName = MethodName or TypeDefaults[typeof(Object)] or "Destroy"
        if type(Object) ~= "function" and not Object[MethodName] then
            warn(string.format(METHOD_NOT_FOUND_ERROR, tostring(Object), tostring(MethodName), debug.traceback(nil, 2)))
        end

        self[Object] = MethodName
        return Object
    end

    function janitor.__index:Remove(Index)
        local This = self[IndicesReference]

        if This then
            local Object = This[Index]

            if Object then
                local MethodName = self[Object]

                if MethodName then
                    if MethodName == true then
                        Object()
                    else
                        local ObjectMethod = Object[MethodName]
                        if ObjectMethod then
                            ObjectMethod(Object)
                        end
                    end

                    self[Object] = nil
                end

                This[Index] = nil
            end
        end

        return self
    end

    function janitor.__index:Get(Index)
        local This = self[IndicesReference]
        if This then
            return This[Index]
        else
            return nil
        end
    end

    function janitor.__index:Cleanup()
        if not self.CurrentlyCleaning then
            self.CurrentlyCleaning = nil
            for Object, MethodName in next, self do
                if Object == IndicesReference then
                    continue
                end

                if MethodName == true then
                    Object()
                else
                    local ObjectMethod = Object[MethodName]
                    if ObjectMethod then
                        ObjectMethod(Object)
                    end
                end

                self[Object] = nil
            end

            local This = self[IndicesReference]
            if This then
                for Index in next, This do
                    This[Index] = nil
                end

                self[IndicesReference] = {}
            end

            self.CurrentlyCleaning = false
        end
    end

    function janitor.__index:Destroy()
        self:Cleanup()
        table.clear(self)
        setmetatable(self, nil)
    end

    janitor.__call = janitor.__index.Cleanup

    local Disconnect = {Connected = true}
    Disconnect.__index = Disconnect
    function Disconnect:Disconnect()
        if self.Connected then
            self.Connected = false
            self.Connection:Disconnect()
        end
    end

    function Disconnect:__tostring()
        return "Disconnect<" .. tostring(self.Connected) .. ">"
    end

    function janitor.__index:LinkToInstance(Object, AllowMultiple)
        local Connection
        local IndexToUse = AllowMultiple and newproxy(false) or LinkToInstanceIndex
        local IsNilParented = Object.Parent == nil
        local ManualDisconnect = setmetatable({}, Disconnect)

        local function ChangedFunction(_DoNotUse, NewParent)
            if ManualDisconnect.Connected then
                _DoNotUse = nil
                IsNilParented = NewParent == nil

                if IsNilParented then
                    task.defer(function()
                        if not ManualDisconnect.Connected then
                            return
                        elseif not Connection.Connected then
                            self:Cleanup()
                        else
                            while IsNilParented and Connection.Connected and ManualDisconnect.Connected do
                                task.wait()
                            end

                            if ManualDisconnect.Connected and IsNilParented then
                                self:Cleanup()
                            end
                        end
                    end)
                end
            end
        end

        Connection = Object.AncestryChanged:Connect(ChangedFunction)
        ManualDisconnect.Connection = Connection

        if IsNilParented then
            ChangedFunction(nil, Object.Parent)
        end

        Object = nil
        return self:Add(ManualDisconnect, "Disconnect", IndexToUse)
    end

    function janitor.__index:LinkToInstances(...)
        local ManualCleanup = Janitor.new()
        for _, Object in ipairs({...}) do
            ManualCleanup:Add(self:LinkToInstance(Object, true), "Disconnect")
        end

        return ManualCleanup
    end

    Janitor = janitor
end

local DrawingESP; do -- ESP
    -- Constants:
    local Camera = Workspace.CurrentCamera

    -- Cache:
    local RunningESPs = {}
    local WorldToViewportPoint = Camera.WorldToViewportPoint
    local IsDescendantOf = game.IsDescendantOf
    local NewCFrame, NewVector2, NewVector3 = CFrame.new, Vector2.new, Vector3.new

    -- Functions:
    local function NewText(Color, Text)
        local Label = Drawing.new("Text")
        Label.Text = Text
        Label.Center = true
        Label.Visible = false
        Label.Position = NewVector2(0, 0)
        Label.Color = Color
        Label.Outline = true
        Label.Transparency = 1
        return Label
    end

    local function NewLine(Color, Thickness)
        local Line = Drawing.new("Line")
        Line.Visible = false
        Line.From = NewVector2(0, 0)
        Line.To = NewVector2(0, 0)
        Line.Color = Color
        Line.Thickness = Thickness
        Line.Transparency = 1
        return Line
    end

    local function ApplyProperties(Array, Properties)
        for i,v in pairs(Array) do
            for x,y in pairs(Properties) do
                v[x] = y
            end
        end
    end

    -- Module:
    local Module = {}
    Module.RunningESPs = RunningESPs
    Module.__index = Module

    function Module.new(Object, Text, Color)
        if RunningESPs[Object] then return RunningESPs[Object] end;

        -- Default Values
        Text = Text or "";
        Color = Color or Color3.fromRGB(255, 255, 255);

        -- Constructor:
        local self = Object:IsA("Player") and Module.__newPlayer(Object, Text, Color) or Module.__newRig(Object, Text, Color);
        Object.AncestryChanged:Connect(function() self:Destroy() end);
        return self;
    end

    function Module.__newPlayer(Player, Text, Color)
        local _Janitor = Janitor.new();
        local self = setmetatable({
            Visible = true;
            Text = Text;
            Color3 = Color;
            _Object = Player;
            _Label = _Janitor:Add(NewText(Color, Text), "Remove"),
            _Library = {
                TL1 = _Janitor:Add(NewLine(Color, 2), "Remove"),
                TL2 = _Janitor:Add(NewLine(Color, 2), "Remove"),
        
                TR1 = _Janitor:Add(NewLine(Color, 2), "Remove"),
                TR2 = _Janitor:Add(NewLine(Color, 2), "Remove"),
        
                BL1 = _Janitor:Add(NewLine(Color, 2), "Remove"),
                BL2 = _Janitor:Add(NewLine(Color, 2), "Remove"),
        
                BR1 = _Janitor:Add(NewLine(Color, 2), "Remove"),
                BR2 = _Janitor:Add(NewLine(Color, 2), "Remove")
            };

            _Janitor = _Janitor;
        }, Module)
        local Library = self._Library
        task.defer(function()
            local TXT = self._Label
            local TL1 = Library.TL1
            local TL2 = Library.TL2
        
            local TR1 = Library.TR1
            local TR2 = Library.TR2
        
            local BL1 = Library.BL1
            local BL2 = Library.BL2
        
            local BR1 = Library.BR1
            local BR2 = Library.BR2

            local Character = Player.Character or Player.CharacterAdded:Wait()
            local Humanoid = Character:FindFirstChildWhichIsA("Humanoid")
            local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart", 4)
            while not Humanoid do
                Humanoid = Character:FindFirstChildWhichIsA("Humanoid");
                task.wait();
            end
            _Janitor:Add(Player.CharacterAdded:Connect(function(character)
                Character = character
                Humanoid = character:WaitForChild("Humanoid", 4)
                HumanoidRootPart = character:WaitForChild("HumanoidRootPart", 4)
            end))
            _Janitor:Add(RunService.RenderStepped:Connect(function()
                if IsDescendantOf(Character, Workspace) and Humanoid.Health > 0 then
                    local ViewportPoint, OnScreen = WorldToViewportPoint(Camera, HumanoidRootPart.Position)
                    if OnScreen and ViewportPoint.Z < 500 then
                        local Position = NewCFrame(HumanoidRootPart.CFrame.Position, HumanoidRootPart.CFrame.Position + -Camera.CFrame.LookVector.Unit)
                        local Size = NewVector3(HumanoidRootPart.Size.X, HumanoidRootPart.Size.Y * 1.5, HumanoidRootPart.Size.Z)
                        local SizeX = Size.X
                        local SizeY = Size.Y
                        local TP = WorldToViewportPoint(Camera, (Position * NewCFrame(0, SizeY, 0)).Position)
                        local TL = WorldToViewportPoint(Camera, (Position * NewCFrame(SizeX, SizeY, 0)).Position)
                        local TR = WorldToViewportPoint(Camera, (Position * NewCFrame(-SizeX, SizeY, 0)).Position)
                        local BL = WorldToViewportPoint(Camera, (Position * NewCFrame(SizeX, -SizeY, 0)).Position)
                        local BR = WorldToViewportPoint(Camera, (Position * NewCFrame(-SizeX, -SizeY, 0)).Position)

                        local Magnitude = (Camera.CFrame.Position - HumanoidRootPart.Position).Magnitude
                        local offset = math.clamp(750 / Magnitude, 2, 300)

                        TXT.Text = self.Text
                        TXT.Position = NewVector2(TP.X, TP.Y - 30)
                        TXT.Size = 25
                        TXT.Visible = self.Visible

                        TL1.From = NewVector2(TL.X, TL.Y)
                        TL1.To = NewVector2(TL.X + offset, TL.Y)
                        TL2.From = NewVector2(TL.X, TL.Y)
                        TL2.To = NewVector2(TL.X, TL.Y + offset)

                        TR1.From = NewVector2(TR.X, TR.Y)
                        TR1.To = NewVector2(TR.X - offset, TR.Y)
                        TR2.From = NewVector2(TR.X, TR.Y)
                        TR2.To = NewVector2(TR.X, TR.Y + offset)

                        BL1.From = NewVector2(BL.X, BL.Y)
                        BL1.To = NewVector2(BL.X + offset, BL.Y)
                        BL2.From = NewVector2(BL.X, BL.Y)
                        BL2.To = NewVector2(BL.X, BL.Y - offset)

                        BR1.From = NewVector2(BR.X, BR.Y)
                        BR1.To = NewVector2(BR.X - offset, BR.Y)
                        BR2.From = NewVector2(BR.X, BR.Y)
                        BR2.To = NewVector2(BR.X, BR.Y - offset)

                        local Thickness = math.clamp(100 / Magnitude, 1, 4)
                        ApplyProperties(Library, { Visible = self.Visible, Thickness = Thickness }) --0.1 is min thickness, 6 is max
                    else
                        ApplyProperties(Library, { Visible = false })
                        TXT.Visible = false
                    end
                else
                    ApplyProperties(Library, { Visible = false })
                    TXT.Visible = false
                end
            end))
        end)
        RunningESPs[Player] = self
        return self
    end

    function Module.__newRig(Character, Text, Color)
        local _Janitor = Janitor.new();
        local self = setmetatable({
            Visible = true;
            Text = Text;
            Color3 = Color;
            _Object = Character;
            _Label = _Janitor:Add(NewText(Color, Text), "Remove"),
            _Library = {
                TL1 = _Janitor:Add(NewLine(Color, 2), "Remove"),
                TL2 = _Janitor:Add(NewLine(Color, 2), "Remove"),
        
                TR1 = _Janitor:Add(NewLine(Color, 2), "Remove"),
                TR2 = _Janitor:Add(NewLine(Color, 2), "Remove"),
        
                BL1 = _Janitor:Add(NewLine(Color, 2), "Remove"),
                BL2 = _Janitor:Add(NewLine(Color, 2), "Remove"),
        
                BR1 = _Janitor:Add(NewLine(Color, 2), "Remove"),
                BR2 = _Janitor:Add(NewLine(Color, 2), "Remove")
            };

            _Janitor = _Janitor;
        }, Module)
        local Library = self._Library
        task.defer(function()
            local TXT = self._Label
            local TL1 = Library.TL1
            local TL2 = Library.TL2
        
            local TR1 = Library.TR1
            local TR2 = Library.TR2
        
            local BL1 = Library.BL1
            local BL2 = Library.BL2
        
            local BR1 = Library.BR1
            local BR2 = Library.BR2

            local Humanoid = Character:FindFirstChildWhichIsA("Humanoid");
            local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart", 4);
            while not Humanoid do
                Humanoid = Character:FindFirstChildWhichIsA("Humanoid");
                task.wait();
            end;

            _Janitor:Add(RunService.RenderStepped:Connect(function()
                if IsDescendantOf(Character, Workspace) and Humanoid.Health > 0 then
                    local ViewportPoint, OnScreen = WorldToViewportPoint(Camera, HumanoidRootPart.Position)
                    if OnScreen and ViewportPoint.Z < 500 then
                        local Position = NewCFrame(HumanoidRootPart.CFrame.Position, HumanoidRootPart.CFrame.Position + -Camera.CFrame.LookVector.Unit)
                        local Size = NewVector3(HumanoidRootPart.Size.X, HumanoidRootPart.Size.Y * 1.5, HumanoidRootPart.Size.Z)
                        local SizeX = Size.X
                        local SizeY = Size.Y
                        local TP = WorldToViewportPoint(Camera, (Position * NewCFrame(0, SizeY, 0)).Position)
                        local TL = WorldToViewportPoint(Camera, (Position * NewCFrame(SizeX, SizeY, 0)).Position)
                        local TR = WorldToViewportPoint(Camera, (Position * NewCFrame(-SizeX, SizeY, 0)).Position)
                        local BL = WorldToViewportPoint(Camera, (Position * NewCFrame(SizeX, -SizeY, 0)).Position)
                        local BR = WorldToViewportPoint(Camera, (Position * NewCFrame(-SizeX, -SizeY, 0)).Position)

                        local Magnitude = (Camera.CFrame.Position - HumanoidRootPart.Position).Magnitude
                        local offset = math.clamp(750 / Magnitude, 2, 300)

                        TXT.Text = self.Text
                        TXT.Position = NewVector2(TP.X, TP.Y - 30)
                        TXT.Size = 25
                        TXT.Visible = self.Visible

                        TL1.From = NewVector2(TL.X, TL.Y)
                        TL1.To = NewVector2(TL.X + offset, TL.Y)
                        TL2.From = NewVector2(TL.X, TL.Y)
                        TL2.To = NewVector2(TL.X, TL.Y + offset)

                        TR1.From = NewVector2(TR.X, TR.Y)
                        TR1.To = NewVector2(TR.X - offset, TR.Y)
                        TR2.From = NewVector2(TR.X, TR.Y)
                        TR2.To = NewVector2(TR.X, TR.Y + offset)

                        BL1.From = NewVector2(BL.X, BL.Y)
                        BL1.To = NewVector2(BL.X + offset, BL.Y)
                        BL2.From = NewVector2(BL.X, BL.Y)
                        BL2.To = NewVector2(BL.X, BL.Y - offset)

                        BR1.From = NewVector2(BR.X, BR.Y)
                        BR1.To = NewVector2(BR.X - offset, BR.Y)
                        BR2.From = NewVector2(BR.X, BR.Y)
                        BR2.To = NewVector2(BR.X, BR.Y - offset)

                        local Thickness = math.clamp(100 / Magnitude, 1, 4)
                        ApplyProperties(Library, { Visible = self.Visible, Thickness = Thickness }) --0.1 is min thickness, 6 is max
                    else
                        ApplyProperties(Library, { Visible = false })
                        TXT.Visible = false
                    end
                else
                    ApplyProperties(Library, { Visible = false })
                    TXT.Visible = false
                end
            end))
            _Janitor:Add(function()
                RunningESPs[self._Object] = nil;
            end)
        end)

        _Janitor:LinkToInstance(Character);
        RunningESPs[Character] = self
        return self
    end

    function Module:ChangeColor(Value)
        assert(typeof(Value) == "Color3", string.format("Invalid argument #1: Color3 expected, got %s instead!", typeof(Value)))
        self.Color3 = Value
        ApplyProperties(self._Library, {Color = Value})
        self._Label.Color = Value
    end

    function Module:Destroy()
        self._Janitor:Destroy();
    end

    -- Export:
    DrawingESP = Module
end

local DrawingRadar; do --Radar
    -- Constants:
    local GuiService = game:GetService("GuiService")
    local UserInputService = game:GetService("UserInputService")
    
    local LocalPlayer = Players.LocalPlayer
    local Camera = Workspace.CurrentCamera
    
    -- Cache:
    local IsDescendantOf = game.IsDescendantOf
    local NewVector2, NewVector3, NewCFrame = Vector2.new, Vector3.new, CFrame.new
    
    -- Functions:
    local function NewCircle(Transparency, Color, Radius, Filled, Thickness)
        local Circle = Drawing.new("Circle")
        Circle.Transparency = Transparency
        Circle.Color = Color
        Circle.Visible = false
        Circle.Thickness = Thickness
        Circle.Position = Vector2.new(0, 0)
        Circle.Radius = Radius
        Circle.NumSides = math.clamp(Radius * 55 / 100, 10, 75)
        Circle.Filled = Filled
        return Circle
    end
    
    local function GetRelative(Position)
        local Character = LocalPlayer.Character
        if Character then
            local HumanoidRootPart = Character.PrimaryPart or Character:FindFirstChild("HumanoidRootPart")
            if HumanoidRootPart then
                local c = Camera.CFrame.Position
                local RootPosition = HumanoidRootPart.Position
                local CameraPosition = NewVector3(c.X, RootPosition.Y, c.Z)
                local NewCF = NewCFrame(RootPosition, CameraPosition)
                local ObjectSpace = NewCF:PointToObjectSpace(Position)
                return NewVector2(ObjectSpace.X, ObjectSpace.Z);
            end
        end
        return NewVector2(0, 0);
    end
    
    -- Component:
    local RadarDot = {}
    RadarDot.__index = RadarDot
    
    function RadarDot.new(Radar, Adornee, Color)
        Color = Color or Color3.fromRGB(60, 170, 255)
        local self = setmetatable({
            Color3 = Color;
            _Adornee = Adornee;
            _Dot = NewCircle(1, Color, 3, true, 1);
            _Janitor = Janitor.new();
        }, RadarDot)
        local PlayerDot = self._Janitor:Add(self._Dot, "Remove")
        self._Janitor:Add(RunService.RenderStepped:Connect(function()
            if IsDescendantOf(Adornee, Workspace) and Radar.Visible then
                local Relative = GetRelative(Adornee.Position)
                local NewPosition = Radar.Position - Relative
    
                local Delta = Radar.Position - NewPosition
                local Magnitude = Delta.Magnitude
                if Magnitude < (Radar.Radius - 2) then
                    PlayerDot.Radius = 3
                    PlayerDot.Position = NewPosition
                else
                    local Offset = Delta.Unit * (Magnitude - Radar.Radius)
                    PlayerDot.Radius = 2
                    PlayerDot.Position = NewVector2(NewPosition.X + Offset.X, NewPosition.Y + Offset.Y)
                end
                PlayerDot.Visible = true
            else
                PlayerDot.Visible = false
            end
        end))
    
        Radar._Janitor:Add(self._Janitor)
        self._Janitor:LinkToInstance(Adornee)
    
        return self
    end
    
    function RadarDot:ChangeColor(Value)
        assert(typeof(Value) == "Color3", string.format("Invalid argument #1: Color3 expected, got %s instead!", typeof(Value)))
        self.Color3 = Value
        self._Dot.Color = Value
    end
    
    function RadarDot:Destroy()
        self._Janitor:Destroy()
    end
    
    -- Module:
    local Module = {
        CurrentDots = {}
    }
    Module.__index = Module
    
    function Module.new(Position, Radius)
        local self = setmetatable({
            Position = Position or NewVector2(200, 200);
            Radius = Radius or 100;
            Visible = true;
            _Library = {};
            _Janitor = Janitor.new()
        }, Module)
    
        -- Radar:
        local RadarBackground = self._Janitor:Add(NewCircle(0.9, Color3.fromRGB(10, 10, 10), self.Radius, true, 1), "Remove")
        local RadarBorder = self._Janitor:Add(NewCircle(0.75, Color3.fromRGB(75, 75, 75), self.Radius, false, 3), "Remove")
        RadarBackground.Position = self.Position
        RadarBorder.Position = self.Position
        RadarBorder.Visible = true
        RadarBackground.Visible = true
    
        -- Origin:
        local Origin = Drawing.new("Triangle")
        Origin.Visible = true
        Origin.Thickness = 1
        Origin.Filled = true
        Origin.Color = Color3.fromRGB(255, 255, 255)
        Origin.PointA = self.Position + NewVector2(0, -4)
        Origin.PointB = self.Position + NewVector2(-3, 4)
        Origin.PointC = self.Position + NewVector2(3, 4)
        
        self._Janitor:Add(RunService.RenderStepped:Connect(function()
            if self.Visible then
                RadarBackground.Visible = true
                RadarBorder.Visible = true
                Origin.Visible = true
            else
                RadarBackground.Visible = false
                RadarBorder.Visible = false
                Origin.Visible = false
            end
        end))

        -- Draggable:
        task.spawn(function()
            local Inset = GuiService:GetGuiInset()
    
            local Dragging = false
            local Offset = Vector2.new(0, 0)
            UserInputService.InputBegan:Connect(function(Input)
                local MousePosition = Input.Position
                if Input.UserInputType == Enum.UserInputType.MouseButton1 and (Vector2.new(MousePosition.X, MousePosition.Y) - self.Position).Magnitude < self.Radius then
                    Offset = self.Position - NewVector2(Input.Position.X, Input.Position.Y)
                    Dragging = true
                end
            end)
    
            UserInputService.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 then
                    Dragging = false
                end
            end)
    
            local MouseIcon = NewCircle(1, Color3.fromRGB(255, 255, 255), 3, true, 1)
            self._Janitor:Add(RunService.RenderStepped:Connect(function()
                local MouseLocation = UserInputService:GetMouseLocation()
                if (MouseLocation - self.Position).Magnitude < self.Radius then
                    MouseIcon.Position = MouseLocation
                    MouseIcon.Visible = true
                else
                    MouseIcon.Visible = false
                end
                if Dragging then
                    self.Position = Vector2.new(MouseLocation.X, MouseLocation.Y - Inset.Y) + Offset
                    RadarBackground.Position = self.Position
                    RadarBorder.Position = self.Position
                    Origin.PointA = self.Position + NewVector2(0, -4)
                    Origin.PointB = self.Position + NewVector2(-3, 4)
                    Origin.PointC = self.Position + NewVector2(3, 4)
                end
            end))
        end)
    
        return self
    end
    
    function Module:CreateDot(Adornee, Color)
        if Module.CurrentDots[Adornee] then return Module.CurrentDots[Adornee] end
        local NewDot = RadarDot.new(self, Adornee, Color)
        Module.CurrentDots[Adornee] = NewDot
        return NewDot
    end
    
    function Module:FetchDot(Adornee)
        return Module.CurrentDots[Adornee]
    end
    
    function Module:Destroy()
        self._Janitor:Destroy()
    end

    Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        local camera = Workspace.CurrentCamera
        if camera then Camera = camera end;
    end)
    
    -- Export:
    DrawingRadar = Module
end

local SimplePath; do
    local DEFAULT_SETTINGS = {

        TIME_VARIANCE = 0.07;
    
        COMPARISON_CHECKS = 1;
    
        JUMP_WHEN_STUCK = true;
    }
    
    ---------------------------------------------------------------------
    
    local Players = game:GetService("Players")
    local function output(func, msg)
        func(((func == error and "SimplePath Error: ") or "SimplePath: ")..msg)
    end
    local Path = {
        StatusType = {
            Idle = "Idle";
            Active = "Active";
        };
        ErrorType = {
            LimitReached = "LimitReached";
            TargetUnreachable = "TargetUnreachable";
            ComputationError = "ComputationError";
            AgentStuck = "AgentStuck";
        };
    }
    Path.__index = function(table, index)
        if index == "Stopped" and not table._humanoid then
            output(error, "Attempt to use Path.Stopped on a non-humanoid.")
        end
        return (table._events[index] and table._events[index].Event)
            or (index == "LastError" and table._lastError)
            or (index == "Status" and table._status)
            or Path[index]
    end
    
    --Used to visualize waypoints
    local visualWaypoint = Instance.new("Part")
    visualWaypoint.Name = "FakePlane"
    visualWaypoint.Size = Vector3.new(0.3, 0.3, 0.3)
    visualWaypoint.Anchored = true
    visualWaypoint.CanCollide = false
    visualWaypoint.Material = Enum.Material.Neon
    visualWaypoint.Shape = Enum.PartType.Ball
    
    --[[ PRIVATE FUNCTIONS ]]--
    local function declareError(self, errorType)
        self._lastError = errorType
        self._events.Error:Fire(errorType)
    end
    
    --Create visual waypoints
    local function createVisualWaypoints(waypoints)
        local visualWaypoints = {}
        for _, waypoint in ipairs(waypoints) do
            local visualWaypointClone = visualWaypoint:Clone()
            visualWaypointClone.Position = waypoint.Position
            visualWaypointClone.Color =
                (waypoint == waypoints[#waypoints] and Color3.fromRGB(0, 255, 0))
                or (waypoint.Action == Enum.PathWaypointAction.Jump and Color3.fromRGB(255, 0, 0))
                or Color3.fromRGB(255, 139, 0)
            -- syn.protect_gui(visualWaypointClone);
            visualWaypointClone.Parent = Workspace;
            table.insert(visualWaypoints, visualWaypointClone)
        end
        return visualWaypoints
    end
    
    --Destroy visual waypoints
    local function destroyVisualWaypoints(waypoints)
        if waypoints then
            for _, waypoint in ipairs(waypoints) do
                waypoint:Destroy()
            end
        end
        return
    end
    
    --Get initial waypoint for non-humanoid
    local function getNonHumanoidWaypoint(self)
        --Account for multiple waypoints that are sometimes in the same place
        for i = 2, #self._waypoints do
            if (self._waypoints[i].Position - self._waypoints[i - 1].Position).Magnitude > 0.1 then
                return i
            end
        end
        return 2
    end
    
    --Make NPC jump
    local function setJumpState(self)
        pcall(function()
            if self._humanoid:GetState() ~= Enum.HumanoidStateType.Jumping and self._humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
                self._humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end)
    end
    
    --Primary move function
    local function move(self)
        if self._waypoints[self._currentWaypoint].Action == Enum.PathWaypointAction.Jump then
            setJumpState(self)
        end
        self._humanoid:MoveTo(self._waypoints[self._currentWaypoint].Position)
    end
    
    --Disconnect MoveToFinished connection when pathfinding ends
    local function disconnectMoveConnection(self)
        self._moveConnection:Disconnect()
        self._moveConnection = nil
    end
    
    --Fire the WaypointReached event
    local function invokeWaypointReached(self)
        local lastWaypoint = self._waypoints[self._currentWaypoint - 1]
        local nextWaypoint = self._waypoints[self._currentWaypoint]
        self._events.WaypointReached:Fire(self._agent, lastWaypoint, nextWaypoint)
    end
    
    local function moveToFinished(self, reached)
    
        --Handle case for non-humanoids
        if not self._humanoid then
            if reached and self._currentWaypoint + 1 <= #self._waypoints then
                invokeWaypointReached(self)
                self._currentWaypoint += 1
            elseif reached then
                self._visualWaypoints = destroyVisualWaypoints(self._visualWaypoints)
                self._target = nil
                self._events.Reached:Fire(self._agent, self._waypoints[self._currentWaypoint])
            else
                self._visualWaypoints = destroyVisualWaypoints(self._visualWaypoints)
                self._target = nil
                declareError(self, self.ErrorType.TargetUnreachable)
            end
            return
        end
    
        if reached and self._currentWaypoint + 1 <= #self._waypoints  then --Waypoint reached
            if self._currentWaypoint + 1 < #self._waypoints then
                invokeWaypointReached(self)
            end
            self._currentWaypoint += 1
            move(self)
        elseif reached then --Target reached, pathfinding ends
            disconnectMoveConnection(self)
            self._status = Path.StatusType.Idle
            self._visualWaypoints = destroyVisualWaypoints(self._visualWaypoints)
            self._events.Reached:Fire(self._agent, self._waypoints[self._currentWaypoint])
        else --Target unreachable
            disconnectMoveConnection(self)
            self._status = Path.StatusType.Idle
            self._visualWaypoints = destroyVisualWaypoints(self._visualWaypoints)
            declareError(self, self.ErrorType.TargetUnreachable)
        end
    end
    
    --Refer to Settings.COMPARISON_CHECKS
    local function comparePosition(self)
        if self._currentWaypoint == #self._waypoints then return end
        self._position._count = ((self._agent.PrimaryPart.Position - self._position._last).Magnitude <= 0.07 and (self._position._count + 1)) or 0
        self._position._last = self._agent.PrimaryPart.Position
        if self._position._count >= self._settings.COMPARISON_CHECKS then
            if self._settings.JUMP_WHEN_STUCK then
                setJumpState(self)
            end
            declareError(self, self.ErrorType.AgentStuck)
        end
    end
    
    --[[ STATIC METHODS ]]--
    function Path.GetNearestCharacter(fromPosition)
        local character, dist = nil, math.huge
        for _, player in ipairs(Players:GetPlayers()) do
            if player.Character and (player.Character.PrimaryPart.Position - fromPosition).Magnitude < dist then
                character, dist = player.Character, (player.Character.PrimaryPart.Position - fromPosition).Magnitude
            end
        end
        return character
    end
    
    --[[ CONSTRUCTOR ]]--
    function Path.new(agent, agentParameters, override)
        if not (agent and agent:IsA("Model") and agent.PrimaryPart) then
            output(error, "Pathfinding agent must be a valid Model Instance with a set PrimaryPart.")
        end
    
        local self = setmetatable({
            _settings = override or DEFAULT_SETTINGS;
            _events = {
                Reached = Instance.new("BindableEvent");
                WaypointReached = Instance.new("BindableEvent");
                Blocked = Instance.new("BindableEvent");
                Error = Instance.new("BindableEvent");
                Stopped = Instance.new("BindableEvent");
            };
            _agent = agent;
            _humanoid = agent:FindFirstChildOfClass("Humanoid");
            _path = PathfindingService:CreatePath(agentParameters);
            _status = "Idle";
            _t = 0;
            _position = {
                _last = Vector3.new();
                _count = 0;
            };
        }, Path)
    
        --Configure settings
        for setting, value in pairs(DEFAULT_SETTINGS) do
            self._settings[setting] = self._settings[setting] == nil and value or self._settings[setting]
        end
    
        --Path blocked connection
        self._path.Blocked:Connect(function(...)
            if (self._currentWaypoint <= ... and self._currentWaypoint + 1 >= ...) and self._humanoid then
                setJumpState(self)
                self._events.Blocked:Fire(self._agent, self._waypoints[...])
            end
        end)
    
        return self
    end
    
    
    --[[ NON-STATIC METHODS ]]--
    function Path:Destroy()
        for _, event in ipairs(self._events) do
            event:Destroy()
        end
        self._events = nil
        if rawget(self, "Visualize") then
            self._visualWaypoints = destroyVisualWaypoints(self._visualWaypoints)
        end
        self._path:Destroy()
        setmetatable(self, nil)
        for k, _ in pairs(self) do
            self[k] = nil
        end
    end
    
    function Path:Stop()
        if not self._humanoid then
            output(error, "Attempt to call Path:Stop() on a non-humanoid.")
            return
        end
        if self._status == Path.StatusType.Idle then
            output(function(m)
                warn(debug.traceback(m))
            end, "Attempt to run Path:Stop() in idle state")
            return
        end
        disconnectMoveConnection(self)
        self._status = Path.StatusType.Idle
        self._visualWaypoints = destroyVisualWaypoints(self._visualWaypoints)
        self._events.Stopped:Fire(self._model)
    end
    
    function Path:Run(target)
    
        --Non-humanoid handle case
        if not target and not self._humanoid and self._target then
            moveToFinished(self, true)
            return
        end
    
        --Parameter check
        if not (target and (typeof(target) == "Vector3" or target:IsA("BasePart"))) then
            output(error, "Pathfinding target must be a valid Vector3 or BasePart.")
        end
    
        --Refer to Settings.TIME_VARIANCE
        if os.clock() - self._t <= self._settings.TIME_VARIANCE and self._humanoid then
            task.wait(os.clock() - self._t)
            declareError(self, self.ErrorType.LimitReached)
            return false
        elseif self._humanoid then
            self._t = os.clock()
        end
    
        --Compute path
        local pathComputed, _ = pcall(function()
            self._path:ComputeAsync(self._agent.PrimaryPart.Position, (typeof(target) == "Vector3" and target) or target.Position)
        end)
    
        --Make sure path computation is successful
        if not pathComputed
            or self._path.Status == Enum.PathStatus.NoPath
            or #self._path:GetWaypoints() < 2
            or (self._humanoid and self._humanoid:GetState() == Enum.HumanoidStateType.Freefall) then
            self._visualWaypoints = destroyVisualWaypoints(self._visualWaypoints)
            task.wait()
            declareError(self, self.ErrorType.ComputationError)
            return false
        end
    
        --Set status to active; pathfinding starts
        self._status = (self._humanoid and Path.StatusType.Active) or Path.StatusType.Idle
        self._target = target

        --Initialize waypoints
        self._waypoints = self._path:GetWaypoints()
        self._currentWaypoint = 2
    
        --Refer to Settings.COMPARISON_CHECKS
        if self._humanoid then
            comparePosition(self)
        end
    
        --Visualize waypoints
        destroyVisualWaypoints(self._visualWaypoints)
        self._visualWaypoints = (self.Visualize and createVisualWaypoints(self._waypoints))
    
        --Create a new move connection if it doesn't exist already
        self._moveConnection = self._humanoid and (self._moveConnection or self._humanoid.MoveToFinished:Connect(function(...)
            moveToFinished(self, ...)
        end))
    
        --Begin pathfinding
        if self._humanoid then
            self._humanoid:MoveTo(self._waypoints[self._currentWaypoint].Position)
        elseif #self._waypoints == 2 then
            self._target = nil
            self._visualWaypoints = destroyVisualWaypoints(self._visualWaypoints)
            self._events.Reached:Fire(self._agent, self._waypoints[2])
        else
            self._currentWaypoint = getNonHumanoidWaypoint(self)
            moveToFinished(self, true)
        end
        return true
    end
    
    SimplePath = Path;
end

local Library = loadstring(game:HttpGet("https://lindseyhost.com/UI/LinoriaLib.lua"))();

-- Constants:
local LocalPlayer = Players.LocalPlayer;
local Camera = Workspace.CurrentCamera;

local CratesFolder = Workspace.Debris.SupplyCrates;
local ScrapSpawns = Workspace.Filter.ScrapSpawns;
local Timer = ReplicatedStorage.Timer
local PowerLevel = ReplicatedStorage.PowerValues.PowerLevel

local Radar = DrawingRadar.new();
local Glow = Instance.new("PointLight");
local RakeModifer = Instance.new("PathfindingModifier");
local RakePart = Instance.new("Part");

local AgentParameters = {
    AgentRadius = 1;
    AgentHeight = 4;
    AgentCanJump = true;
    WaypointSpacing = 10;
    Costs = {
        Rake = 100;
    }
}

local icons = {
    location = "https://i.ibb.co/FB61M8f/location.png",
    crate = "https://i.ibb.co/DLDzY81/supply-crate.png",
    flare = "https://i.ibb.co/2WgVW84/flare-gun.png",
    scrap = "https://i.ibb.co/W3z1ZZK/scrap.png",
}

-- Variables:
local locationESPs = {
    Cave = nil;
    Shop = nil;
    PowerStation = nil;
    BaseCamp = nil;
    SafeHouse = nil;
    ObservationTower = nil;
};
local supplyCrateESPs = {}
local flareGunESPs = {}
local scrapESPs = {}

local M_Hs = {};

local rake = nil;
local scraps = {};

-- Functions:
local function angleDistance(a, b)
    return math.deg(math.acos(a:Dot(b)))
end

local function secondsToMS(seconds)
    return string.format("%02i:%02i", math.floor(seconds / 60), math.floor(seconds % 60))
end

local function validCharacter(character)
    if character and character:IsA("Model") and character:IsDescendantOf(Workspace) then
        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
        if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
            local humanoid = character:FindFirstChildWhichIsA("Humanoid")
            if humanoid and humanoid.Health > 0 then
                return true
            end
        end
    end
    return false;
end

local function createBot(character)
    repeat task.wait() until validCharacter(character);
    local Humanoid = character.Humanoid;
    local HumanoidRootPart = character.HumanoidRootPart;
    local Path = SimplePath.new(character, AgentParameters);

    local places = {
        Vector3.new(-292.2, 19.4, -192.6), -- Power Station
        Vector3.new(-46, 17.1, 171.2), -- Base Camp
        Vector3.new(-353.8, 15.5, 72.8), -- Safe House
        Vector3.new(21.7, 17.1, -81.9), -- Observation Tower
    };
    local index = 1;

    local function notify(task)
        if Toggles.BotNotifications.Value then
            Library:Notify(string.format("Bot Task: %s", task));
        end
    end

    local function sortPlacesByDistance(position)
        local sorted = {
            1, -- Power Station
            2, -- Base Camp
            3, -- Safe House
            4, -- Observation Tower
        };
        table.sort(sorted, function(a, b)
            local aDistance = (places[a] - (position or HumanoidRootPart.Position)).Magnitude;
            local bDistance = (places[b] - (position or HumanoidRootPart.Position)).Magnitude;
            return aDistance < bDistance;
        end)
        return sorted;
    end

    repeat
        if Toggles.Bot.Value then
            while Toggles.Bot.Value and validCharacter(character) do
                index = sortPlacesByDistance()[1];
                if validCharacter(rake) then
                    local rakeIndex = sortPlacesByDistance(rake.HumanoidRootPart.Position)[1];
                else
                    Path:Run(places[index]);
                    Path.Reached:Wait();
                end
                task.wait();
            end
        end
        task.wait();
    until not validCharacter(character);
end

local function createMarker(name, color, position, size, image)
    local self = {
        Name = name,
        color = color or Color3.new(1, 1, 1),
        Visible = true,
        Size = size or 1,
        Position = position or Vector3.new(0, 0, 0),
        Destroyed = false,
        _Image = Drawing.new("Image"),
        _Label = Drawing.new("Text"),
        _Janitor = Janitor.new()
    };
    self._Image.Data = image or icons.location;

    self._Label.Text = name;
    self._Label.Color = self.color;
    self._Label.Outline = true;
    self._Label.Center = true;

    function self:Update()
        if self.Visible then
            local viewportPoint = Camera:WorldToViewportPoint(self.Position);
            if viewportPoint.Z > 0 then
                local viewportPosition = Vector2.new(viewportPoint.X, viewportPoint.Y);
                local distance = math.min(viewportPoint.Z, 500);

                -- Image:
                local imageSize = Vector2.new(1, 1) * (6e3 / distance) * self.Size;
                self._Image.Position = viewportPosition + Vector2.new(-imageSize.X / 2, -imageSize.Y);
                self._Image.Size = imageSize;

                -- Text:
                local textSize = 3e3 / distance * self.Size;
                self._Label.Position = viewportPosition + Vector2.new(0, (distance * self.Size) / 100);
                self._Label.Size = textSize;
                self._Label.Color = self.color;

                -- Visibility:
                self._Image.Visible = true;
                self._Label.Visible = true;
            else
                self._Image.Visible = false;
                self._Label.Visible = false;
            end
        else
            self._Image.Visible = false;
            self._Label.Visible = false;
        end
    end

    function self:Destroy()
        if self.Destroyed then return end;
        self.Destroyed = true;
        self._Janitor:Destroy();
        self.Update = function() end;
    end

    self._Janitor:Add(self._Label, "Remove");
    self._Janitor:Add(self._Image, "Remove");

    return self;
end

local function rakeAdded(monster)
    rake = monster;

    -- Visuals:
    local ESP = DrawingESP.new(monster, "Rake", Color3.new(1, 0, 0));
    Radar:CreateDot(monster:WaitForChild("HumanoidRootPart", 5), Color3.new(1, 0, 0));

    -- Refresh:
    local humanoid = monster:FindFirstChildWhichIsA("Humanoid")
    humanoid.HealthChanged:Connect(function(health)
        ESP.Text = ("Rake [%s/%s]"):format(math.floor(health), humanoid.MaxHealth);
    end)
    ESP.Text = ("Rake [%s/%s]"):format(math.floor(humanoid.Health), humanoid.MaxHealth);
end

local function flareAdded(flare)
    local marker = createMarker("Flare Gun", Color3.fromRGB(255, 0, 0), flare:WaitForChild("FlareGun").Position, 0.5, icons.flare);
    table.insert(flareGunESPs, marker);
    if Toggles.FlareNotifications.Value then Library:Notify("Flare Gun has spawned!") end;
    flare.AncestryChanged:Connect(function(_, parent)
        if parent == nil then
            marker:Destroy();
            table.remove(flareGunESPs, table.find(flareGunESPs, marker));
        end
    end)
end

local function crateAdded(crate)
    local hitbox = crate:WaitForChild("MainHitBox", 5);
    if hitbox then
        local marker = createMarker("Supply Crate", Color3.fromRGB(234, 146, 65), hitbox.Position + Vector3.new(0, 10, 0), 0.75, icons.crate);
        table.insert(supplyCrateESPs, marker);
        if Toggles.CrateNotifications.Value then Library:Notify("Supply Crate has spawned!") end;
        crate.AncestryChanged:Connect(function(_, parent)
            if parent == nil then
                marker:Destroy();
                table.remove(supplyCrateESPs, table.find(supplyCrateESPs, marker));
            end
        end)
        crate.Useable.Changed:Connect(function(value)
            if not value then
                marker:Destroy();
                table.remove(supplyCrateESPs, table.find(supplyCrateESPs, marker));
            end
        end)
    end
end

local function scrapAdded(scrapModel)
    local scrap = scrapModel:WaitForChild("Scrap", 5);
    local points = scrapModel:WaitForChild("PointsVal", 5);
    task.wait(0.5);
    if scrap and points and scrap:IsDescendantOf(ScrapSpawns) then
        local marker = createMarker(string.format("Scrap [%s]", points.Value), Color3.fromRGB(0, 240, 0), scrap.Position, 0.25, icons.scrap)
        table.insert(scrapESPs, marker);
        table.insert(scraps, scrap);
        if Toggles.ScrapNotifications.Value then Library:Notify("Metal Scrap has spawned!") end;
        scrapModel.AncestryChanged:Connect(function(child, parent)
            if parent == nil then
                marker:Destroy();
                table.remove(scrapESPs, table.find(scrapESPs, marker));
                table.remove(scraps, table.find(scraps, scrap));
            end
        end)
    end
end

local function playerAdded(player)
    task.wait(0.5);
    local ESP = DrawingESP.new(player, player.DisplayName:sub(1, 15), Color3.new(1, 1, 1));

    player.CharacterAdded:Connect(function(character)
        Radar:CreateDot(character:WaitForChild("HumanoidRootPart", 5), Color3.new(1, 1, 1));
    end)
    local character = player.Character;
    if character then Radar:CreateDot(character:WaitForChild("HumanoidRootPart", 5), Color3.new(1, 1, 1)) end;
end

local function characterAdded(character)
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 5);

    local tools = {};
    LocalPlayer.Backpack.ChildAdded:Connect(function(tool)
        if tool:IsA("Tool") and not table.find(tools, tool) then
            if tool.Name == "StunStick" then
                table.insert(tools, tool);

                local hitPart = tool:WaitForChild("HitPart", 5);
                tool.Activated:Connect(function()
                    task.wait(0.15);
                    if Toggles.Reach.Value then
                        if rake and rake:IsDescendantOf(Workspace) then
                            local delta = (rake.HumanoidRootPart.Position - humanoidRootPart.Position);
                            if delta.Magnitude <= 15 and angleDistance(delta.Unit, humanoidRootPart.CFrame.LookVector.Unit) <= 270 then
                                firetouchinterest(rake, hitPart, 1);
                                task.wait();
                                firetouchinterest(rake, hitPart, 0);
                            end
                        end
                    end
                end)
                return;
            end
        end
    end)

    Glow.Parent = humanoidRootPart;
    return createBot(character);
end

-- Interface:
Library:SetWatermark("Linoria Community (OminousVibes)");
Library:Notify("Loading UI...");

local Window = Library:CreateWindow("Linoria | The Rake REMASTERED");
do -- Legit
    local Tab = Window:AddTab("Legit");

    do -- Character
        local Container = Tab:AddLeftGroupbox("Character");

        Container:AddToggle("InfStamina", { Text = "No Stamina Drain", Default = false });
        Container:AddToggle("CharacterGlow", { Text = "Character Glow", Default = false });
        Container:AddSlider("GlowBrightness", { Text = "Glow Brightness", Min = 0, Max = 10, Default = 1, Rounding = 1, Suffix = "w" });
        Container:AddSlider("GlowRadius", { Text = "Glow Radius", Min = 10, Max = 75, Default = 25, Rounding = 0, Suffix = " studs" });
    end

    do -- AFK
        local Container = Tab:AddRightGroupbox("AFK (WORK IN PROGRESS)");
        Container:AddToggle("Bot", { Text = "AFK Bot", Default = false });
        Container:AddToggle("FarmScraps", { Text = "Farm Scraps", Default = false });
        Container:AddToggle("BotNotifications", { Text = "Status Notifications", Default = false });
        Container:AddToggle("PathVisuals", { Text = "Path Visuals", Default = false });
    end

    do -- Combat Assists
        local Container = Tab:AddLeftGroupbox("Combat Assists");

        Container:AddToggle("Reach", { Text = "Stun Stick Reach (Broken)", Default = false });
    end
end

do -- Visuals
    local Tab = Window:AddTab("Visuals");

    do -- Humanoid ESP
        local Container = Tab:AddLeftGroupbox("Humanoid ESP");
        Container:AddToggle("PlayerESP", { Text = "Players ESP", Default = true });
        Container:AddToggle("RakeESP", { Text = "Rakes ESP", Default = true });
        Container:AddToggle("Radar", { Text = "Radar", Default = true });
    end

    do -- World ESPs
        local Container = Tab:AddRightTabbox("World ESPs");
        
        local Dynamic = Container:AddTab("Interactables");
        Dynamic:AddToggle("ScrapESP", { Text = "Scraps (Points)", Default = true });
        Dynamic:AddToggle("FlareESP", { Text = "Flares", Default = true });
        Dynamic:AddToggle("SupplyCrateESP", { Text = "Supply Crates", Default = true });

        local Locations = Container:AddTab("Locations");
        Locations:AddToggle("Cave", { Text = "Cave", Default = true });
        Locations:AddToggle("Shop", { Text = "Shop", Default = true });
        Locations:AddToggle("PowerStation", { Text = "Power Station", Default = true });
        Locations:AddToggle("BaseCamp", { Text = "Base Camp", Default = true });
        Locations:AddToggle("SafeHouse", { Text = "Safe House", Default = true });
        Locations:AddToggle("ObservationTower", { Text = "Observation Tower", Default = true });
    end
end

do -- Values
    local Tab = Window:AddTab("Values");

    do -- Drops
        local Container = Tab:AddLeftGroupbox("Drop Notifications");

        Container:AddToggle("FlareNotifications", { Text = "Flare", Default = true });
        Container:AddToggle("CrateNotifications", { Text = "Supply Crate", Default = true });
        Container:AddToggle("ScrapNotifications", { Text = "Scrap (Spammy)", Default = false });
    end

    do -- Game
        local Container = Tab:AddRightGroupbox("Game Notifications");

        Container:AddToggle("PowerNotifications", { Text = "Power Level", Default = true })
            :AddKeyPicker("PowerNotifications", { Text = "Notify Power", Default = "G", NoUI = true });
        Container:AddToggle("TimerNotifications", { Text = "Timer", Default = true })
            :AddKeyPicker("TimerNotifications", { Text = "Notify Power", Default = "T", NoUI = true });
    end
end

do -- Settings
    local Tab = Window:AddTab("Settings");

    local function UpdateTheme()
        Library.BackgroundColor = Options.BackgroundColor.Value;
        Library.MainColor = Options.MainColor.Value;
        Library.AccentColor = Options.AccentColor.Value;
        Library.AccentColorDark = Library:GetDarkerColor(Library.AccentColor);
        Library.OutlineColor = Options.OutlineColor.Value;
        Library.FontColor = Options.FontColor.Value;

        Library:UpdateColorsUsingRegistry();
    end;

    local function SetDefault()
        Options.FontColor:SetValueRGB(Color3.fromRGB(255, 255, 255));
        Options.MainColor:SetValueRGB(Color3.fromRGB(28, 28, 28));
        Options.BackgroundColor:SetValueRGB(Color3.fromRGB(20, 20, 20));
        Options.AccentColor:SetValueRGB(Color3.fromRGB(0, 85, 255));
        Options.OutlineColor:SetValueRGB(Color3.fromRGB(50, 50, 50));
        Toggles.Rainbow:SetValue(false);

        UpdateTheme();
    end;

    local Theme = Tab:AddLeftGroupbox("Theme");
    Theme:AddLabel("Background Color"):AddColorPicker("BackgroundColor", { Default = Library.BackgroundColor });
    Theme:AddLabel("Main Color"):AddColorPicker("MainColor", { Default = Library.MainColor });
    Theme:AddLabel("Accent Color"):AddColorPicker("AccentColor", { Default = Library.AccentColor });
    Theme:AddToggle("Rainbow", { Text = "Rainbow Accent Color" });
    Theme:AddLabel("Outline Color"):AddColorPicker("OutlineColor", { Default = Library.OutlineColor });
    Theme:AddLabel("Font Color"):AddColorPicker("FontColor", { Default = Library.FontColor });
    Theme:AddButton("Default Theme", SetDefault);
    Theme:AddToggle("Keybinds", { Text = "Show Keybinds Menu", Default = true }):OnChanged(function()
        Library.KeybindFrame.Visible = Toggles.Keybinds.Value;
    end);
    Theme:AddToggle("Watermark", { Text = "Show Watermark", Default = true }):OnChanged(function()
        Library:SetWatermarkVisibility(Toggles.Watermark.Value);
    end);

    local Credits = Tab:AddRightGroupbox("Credits");
    Credits:AddLabel("Made by: OminousVibes");
    Credits:AddLabel("UI Library: violin#5434");
    Credits:AddLabel("Oral Support: OtarDev#0108");

    RunService.RenderStepped:Connect(function()
        if Toggles.Rainbow.Value then
            if Toggles.Rainbow.Value then
                local Registry = Window.Holder.Visible and Library.Registry or Library.HudRegistry;

                for Idx, Object in next, Registry do
                    for Property, ColorIdx in next, Object.Properties do
                        if ColorIdx == "AccentColor" or ColorIdx == "AccentColorDark" then
                            local Instance = Object.Instance;
                            local yPos = Instance.AbsolutePosition.Y;

                            local Mapped = Library:MapValue(yPos, 0, 1080, 0, 0.5) * 1.5;
                            local Color = Color3.fromHSV((Library.CurrentRainbowHue - Mapped) % 1, 0.8, 1);

                            if ColorIdx == "AccentColorDark" then
                                Color = Library:GetDarkerColor(Color);
                            end;

                            Instance[Property] = Color;
                        end;
                    end;
                end;
            end;
        end;
    end);

    Toggles.Rainbow:OnChanged(function()
        if not Toggles.Rainbow.Value then
            UpdateTheme();
        end;
    end);

    Options.BackgroundColor:OnChanged(UpdateTheme);
    Options.MainColor:OnChanged(UpdateTheme);
    Options.AccentColor:OnChanged(UpdateTheme);
    Options.OutlineColor:OnChanged(UpdateTheme);
    Options.FontColor:OnChanged(UpdateTheme);
end

Toggles.InfStamina:OnChanged(function()
    if Toggles.InfStamina.Value then
        for i,v in ipairs(getconnections(ReplicatedStorage.TKSMNA.Event)) do
            if v.State then
                v:Disable();
            end
        end
    else
        for i,v in ipairs(getconnections(ReplicatedStorage.TKSMNA.Event)) do
            if not v.State then
                v:Enable();
            end
        end
    end
end);
Toggles.CharacterGlow:OnChanged(function() Glow.Enabled = Toggles.CharacterGlow.Value end);
Toggles.Bot:OnChanged(function()
    RakePart.Transparency = Toggles.Bot.Value and 0.2 or 1;
    if Toggles.Bot.Value then
        ContextActionService:BindAction(
            "No Movement",
            function() return Enum.ContextActionResult.Sink end,
            false,
            unpack(Enum.PlayerActions:GetEnumItems())
        );
    else
        ContextActionService:UnbindAction("No Movement");
    end
end);

Options.GlowBrightness:OnChanged(function()
    Glow.Brightness = Options.GlowBrightness.Value;
end);
Options.GlowRadius:OnChanged(function()
    Glow.Range = Options.GlowRadius.Value;
end);
Options.PowerNotifications:OnClick(function()
    Library:Notify(string.format("Power Level: %s%%", math.floor(PowerLevel.Value / 10)));
end)
Options.TimerNotifications:OnClick(function()
    Library:Notify(string.format("Time Left: %s", secondsToMS(Timer.Value)));
end)

Library:Notify("Loaded UI!")

-- Listeners:
Workspace.ChildAdded:Connect(function(child)
    if child.Name == "Rake" then
        task.wait(2); if validCharacter(child) then rakeAdded(child) end;
        return;
    end
    if child.Name == "FlareGunPickUp" then
        return flareAdded(child);
    end
end)
CratesFolder.ChildAdded:Connect(crateAdded);
for i,v in ipairs(ScrapSpawns:GetChildren()) do v.ChildAdded:Connect(scrapAdded) end;

PowerLevel.Changed:Connect(function(value)
    if value == 100 then
        Library:Notify("Power Level reached 10%");
    end
end)
Timer.Changed:Connect(function(value)
    if value == 15 then
        Library:Notify("15 seconds left!");
    end
end)

Players.PlayerAdded:Connect(playerAdded);
LocalPlayer.CharacterAdded:Connect(characterAdded);

RunService.RenderStepped:Connect(function()
    -- Render Visuals:
    for i,v in pairs(DrawingESP.RunningESPs) do
        if v._Object:IsA("Player") then
            v.Visible = Toggles.PlayerESP.Value;
        elseif v._Object.Name == "Rake" then
            v.Visible = Toggles.RakeESP.Value;
        end
    end
    for i,v in pairs(locationESPs) do
        v.Visible = Toggles[i].Value;
        v:Update();
    end
    for i,v in ipairs(scrapESPs) do
        v.Visible = Toggles.ScrapESP.Value;
        v:Update();
    end
    for i,v in ipairs(flareGunESPs) do
        v.Visible = Toggles.FlareESP.Value;
        v:Update();
    end
    for i,v in ipairs(supplyCrateESPs) do
        v.Visible = Toggles.SupplyCrateESP.Value;
        v:Update();
    end
    Radar.Visible = Toggles.Radar.Value

    -- Update Information:
    for i,v in ipairs(getloadedmodules()) do
        if v.Name == "M_H" and not table.find(M_Hs, v) then
            table.insert(M_Hs, v);
            local module = require(v);
            local old;
            old = hookfunction(module.TakeStamina, function(smth, amount)
                if Toggles.InfStamina.Value and amount > 0 then return old(smth, -0.5) end;
                return old(smth, amount);
            end);
        end
    end
    if validCharacter(rake) then
        RakePart.CFrame = rake.HumanoidRootPart.CFrame;
    end
end)
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    local camera = Workspace.CurrentCamera;
    if camera then Camera = camera end;
end)

-- Actions:
Glow.Range = 100;
Glow.Brightness = 1;
Glow.Color = Color3.new(1, 1, 1);
Glow.Shadows = false;
syn.protect_gui(Glow);
if LocalPlayer.Character then Glow.Parent = LocalPlayer.Character:WaitForChild("HumanoidRootPart") end;

RakeModifer.Label = "Rake";
RakeModifer.Parent = RakePart;
RakePart.Name = "FakePlane";
RakePart.CanCollide = false;
RakePart.Anchored = true;
RakePart.Size = Vector3.new(100, 100, 100);
RakePart.Material = Enum.Material.Neon;
RakePart.Color = Color3.new(1, 0, 0);
RakePart.Transparency = 1;
syn.protect_gui(RakePart);
RakePart.Parent = Workspace;


for i,v in pairs(icons) do -- Preload icons
    icons[i] = game:HttpGet(v);
end

for i,v in ipairs(Players:GetPlayers()) do -- Player check
    if v ~= LocalPlayer then task.spawn(playerAdded, v) end;
end
if LocalPlayer.Character then characterAdded(LocalPlayer.Character) end

do -- Rake Check
    local monster = Workspace:FindFirstChild("Rake");
    if monster and validCharacter(monster) then rakeAdded(monster) end;
end

do -- Flare Check
    local flareGun = Workspace:FindFirstChild("FlareGunPickUp");
    if flareGun then
        flareAdded(flareGun);
    end
end

do -- Supply Crate
    local crates = Workspace.Debris.SupplyCrates:GetChildren();
    for i,v in ipairs(crates) do task.spawn(crateAdded, v) end;
end

do -- Scrap Check
    for i,v in ipairs(ScrapSpawns:GetChildren()) do
        local scrapModel = v:GetChildren()[1];
        if scrapModel then scrapAdded(scrapModel) end;
    end
end

do -- Locations
    locationESPs.Cave = createMarker("Cave", Color3.fromRGB(0, 210, 255), Vector3.new(-150, 40, 25), 1, icons.location);
    locationESPs.Shop = createMarker("Shop", Color3.fromRGB(0, 210, 255), Vector3.new(-25, 35, -260), 1, icons.location);
    locationESPs.PowerStation = createMarker("Power Station", Color3.fromRGB(0, 210, 255), Vector3.new(-280, 35, -210), 1, icons.location);
    locationESPs.SafeHouse = createMarker("Safe House", Color3.fromRGB(0, 210, 255), Vector3.new(-365, 40, 65), 1, icons.location);
    locationESPs.ObservationTower = createMarker("Observation Tower", Color3.fromRGB(0, 210, 255), Vector3.new(50, 75, -50), 1, icons.location);
    locationESPs.BaseCamp = createMarker("Base Camp", Color3.fromRGB(0, 210, 255), Vector3.new(-43.9, 35, 204.3), 1, icons.location);
end

return Library:Notify("Loaded [The Rake REMASTERED]!");