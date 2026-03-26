import "lib/schema"

local List = require("terralist")

local function is_text_backend(v)
    return type(v) == "table"
        and type(v.key) ~= "nil"
        and type(v.measure_width) == "function"
        and type(v.measure_height_for_width) == "function"
end

-- ════════════════════════════════════════════════════════════════════════
-- TerraUI: compiler-backed UI framework.
--
-- Four phases, monotonically narrowing sum types:
--   Decl (4 enums) → Bound (3 enums) → Plan (2 enums) → Kernel (0 enums)
--
-- Five schema methods — one per real memoize boundary.
-- Internal traversal methods are plain ASDL methods installed by src/ modules.
--
-- The Kernel compile product follows { fn, state_t }:
--   fn      = run_fn  (terra function)
--   state_t = frame_t (terra struct: params, state, nodes, commands)
--
-- Frame layout is driven by Plan.Component via __getentries hook.
-- Color and Vec2 runtime types carry operator hooks for quote composition.
-- ════════════════════════════════════════════════════════════════════════

local schema TerraUI
    doc "Compiler-backed UI framework. Decl → Bound → Plan → Kernel."

    extern TerraType = terralib.types.istype
    extern TerraQuote = terralib.isquote
    extern TextBackend = is_text_backend

    -- ═══════════════════════════════════════════════════════
    phase Decl
    -- ═══════════════════════════════════════════════════════
        doc "User-authored declarative UI tree. Output of the DSL."

        record Component
            doc "Top-level UI component."
            name: string
            params: Param*
            state: StateSlot*
            themes: ThemeDef*
            widgets: WidgetDef*
            root: Node
        unique
        end

        record Param
            doc "Param."
            name: string
            ty: ValueType
            default: Expr?
        end

        record StateSlot
            doc "StateSlot."
            name: string
            ty: ValueType
            initial: Expr?
        end

        flags ValueType
            doc "ValueType."
            TBool
            TNumber
            TString
            TColor
            TImage
            TVec2
            TAny
        end

        record ThemeDef
            doc "ThemeDef."
            name: string
            parent: string?
            tokens: ThemeToken*
        end

        record ThemeToken
            doc "ThemeToken."
            name: string
            ty: ValueType
            value: Expr
        end

        record ThemeOverride
            doc "ThemeOverride."
            name: string
            value: Expr
        end

        record ThemeScope
            doc "ThemeScope."
            base_theme: string?
            overrides: ThemeOverride*
        end

        record WidgetDef
            doc "WidgetDef."
            name: string
            props: WidgetProp*
            state: StateSlot*
            slots: WidgetSlot*
            parts: WidgetPart*
            root: Node
        end

        record WidgetProp
            doc "WidgetProp."
            name: string
            ty: ValueType
            default: Expr?
        end

        record WidgetSlot
            doc "WidgetSlot."
            name: string
        end

        record WidgetPart
            doc "WidgetPart."
            name: string
        end

        record StylePatch
            doc "StylePatch."
            background: Expr?
            border: Border?
            radius: CornerRadius?
            opacity: Expr?
            text_color: Expr?
            font_id: Expr?
            font_size: Expr?
            letter_spacing: Expr?
            line_height: Expr?
            wrap: WrapMode?
            text_align: TextAlign?
            image_tint: Expr?
        end

        record Node
            doc "UI node: the universal layout/rendering unit."
            id: Id
            part: string?
            theme_scope: ThemeScope?
            visibility: Visibility
            layout: Layout
            decor: Decor
            clip: Clip?
            scroll: Scroll?
            scroll_control: ScrollControl?
            floating: Floating?
            input: Input
            aspect_ratio: Expr?
            leaf: Leaf?
            children: Child*
            id_mode: string?
        end

        enum Id
            doc "Id."
            Auto
            Stable { name: string }
            Indexed { name: string, index: Expr }
        end

        enum Child
            doc "Child."
            NodeChild { value: Node }
            WidgetChild { value: WidgetCall }
            SlotRef { name: string }
        end

        record WidgetCall
            doc "WidgetCall."
            id: Id?
            name: string
            props: PropArg*
            styles: PartStyleArg*
            slots: SlotArg*
            theme_scope: ThemeScope?
        end

        record PropArg
            doc "PropArg."
            name: string
            value: Expr
        end

        record PartStyleArg
            doc "PartStyleArg."
            name: string
            patch: StylePatch
        end

        record SlotArg
            doc "SlotArg."
            name: string
            children: Child*
        end

        record Visibility
            doc "Visibility."
            visible_when: Expr?
            enabled_when: Expr?
        end

        record Layout
            doc "Layout."
            axis: Axis
            width: Size
            height: Size
            padding: Padding
            gap: Expr
            align_x: AlignX
            align_y: AlignY
        end

        flags Axis
            doc "Axis."
            Row
            Column
            Stack
        end

        flags AlignX
            doc "AlignX."
            AlignLeft
            AlignCenterX
            AlignRight
        end

        flags AlignY
            doc "AlignY."
            AlignTop
            AlignCenterY
            AlignBottom
        end

        enum Size
            doc "Size."
            Fit { min: Expr?, max: Expr? }
            Grow { min: Expr?, max: Expr? }
            Fixed { value: Expr }
            Percent { value: Expr }
        end

        record Padding
            doc "Padding."
            left: Expr
            top: Expr
            right: Expr
            bottom: Expr
        end

        record Decor
            doc "Decor."
            background: Expr?
            border: Border?
            radius: CornerRadius?
            opacity: Expr?
        end

        record Border
            doc "Border."
            left: Expr
            top: Expr
            right: Expr
            bottom: Expr
            between_children: Expr
            color: Expr
        end

        record CornerRadius
            doc "CornerRadius."
            top_left: Expr
            top_right: Expr
            bottom_right: Expr
            bottom_left: Expr
        end

        record Clip
            doc "Clip."
            horizontal: boolean
            vertical: boolean
        end

        record Scroll
            doc "Scroll."
            horizontal: boolean
            vertical: boolean
        end

        flags ScrollAxis
            doc "ScrollAxis."
            ScrollAxisX
            ScrollAxisY
        end

        flags ScrollMetricKind
            doc "ScrollMetricKind."
            ScrollOffsetX
            ScrollOffsetY
            ScrollViewportW
            ScrollViewportH
            ScrollContentW
            ScrollContentH
            ScrollMaxX
            ScrollMaxY
            ScrollNeedX
            ScrollNeedY
        end

        flags ScrollControlKind
            doc "ScrollControlKind."
            ScrollThumbKind
            ScrollPageDecKind
            ScrollPageIncKind
        end

        record ScrollControl
            doc "ScrollControl."
            target: Id
            axis: ScrollAxis
            kind: ScrollControlKind
        end

        record Floating
            doc "Floating."
            target: FloatTarget
            element_point: AttachPoint
            parent_point: AttachPoint
            offset_x: Expr
            offset_y: Expr
            expand_w: Expr
            expand_h: Expr
            z_index: Expr
            pointer_capture: PointerCapture
        end

        enum FloatTarget
            doc "FloatTarget."
            FloatParent
            FloatById { id: Id }
        end

        flags AttachPoint
            doc "AttachPoint."
            AttachLeftTop
            AttachTopCenter
            AttachRightTop
            AttachLeftCenter
            AttachCenter
            AttachRightCenter
            AttachLeftBottom
            AttachBottomCenter
            AttachRightBottom
        end

        flags PointerCapture
            doc "PointerCapture."
            Capture
            Passthrough
        end

        record Input
            doc "Input."
            hover: boolean
            press: boolean
            focus: boolean
            wheel: boolean
            cursor: string?
            action: string?
        end

        enum Leaf
            doc "Leaf."
            Text { value: TextLeaf }
            Image { value: ImageLeaf }
            Custom { value: CustomLeaf }
        end

        record TextLeaf
            doc "TextLeaf."
            content: Expr
            style: TextStyle
        end

        record TextStyle
            doc "TextStyle."
            color: Expr
            font_id: Expr
            font_size: Expr
            letter_spacing: Expr
            line_height: Expr
            wrap: WrapMode
            align: TextAlign
        end

        flags WrapMode
            doc "WrapMode."
            WrapWords
            WrapNewlines
            WrapNone
        end

        flags TextAlign
            doc "TextAlign."
            TextAlignLeft
            TextAlignCenter
            TextAlignRight
        end

        record ImageLeaf
            doc "ImageLeaf."
            image_id: Expr
            tint: Expr
            fit: ImageFit
        end

        flags ImageFit
            doc "ImageFit."
            ImageStretch
            ImageContain
            ImageCover
        end

        record CustomLeaf
            doc "CustomLeaf."
            kind: string
            payload: Expr?
        end

        enum Expr
            doc "Expression tree for declarative property bindings."
            BoolLit { v: boolean }
            NumLit { v: number }
            StringLit { v: string }
            ColorLit { r: number, g: number, b: number, a: number }
            Vec2Lit { x: number, y: number }
            ParamRef { name: string }
            StateRef { name: string }
            WidgetPropRef { name: string }
            TokenRef { name: string }
            EnvRef { name: string }
            ScrollMetric { id: Id, metric: ScrollMetricKind }
            Unary { op: string, rhs: Expr }
            Binary { op: string, lhs: Expr, rhs: Expr }
            Select { cond: Expr, yes: Expr, no: Expr }
            Call { fn: string, args: Expr* }
        end

        methods
            doc "Decl → Bound: widget elaboration, ID resolution, theme cascading."
            Component:bind(renderer: string, text_backend_key: string) -> Bound.Component
                doc "Elaborate widgets, resolve IDs, slot params and state."
                status = "real"
                impl = require("src/bind")(types).boundary
                fallback = function(self, err)
                    local B = types.Bound
                    local empty_node = B.Node(0, B.ResolvedId("_fallback", 0),
                        B.Visibility(nil, nil),
                        B.Layout(types.Decl.Row, B.Fit(nil, nil), B.Fit(nil, nil),
                            B.Padding(B.ConstNumber(0), B.ConstNumber(0), B.ConstNumber(0), B.ConstNumber(0)),
                            B.ConstNumber(0), types.Decl.AlignLeft, types.Decl.AlignTop),
                        B.Decor(nil, nil, nil, nil), nil, nil, nil, nil,
                        B.Input(false, false, false, false, nil, nil), nil, nil, List())
                    local key = B.SpecializationKey("default", "default", List(), List(), empty_node)
                    return B.Component(self.name or "error", List(), List(), key, empty_node)
                end
        end
    end

    -- ═══════════════════════════════════════════════════════
    phase Bound
    -- ═══════════════════════════════════════════════════════
        doc "Elaborated UI tree. Widgets expanded, IDs resolved, params slotted."

        record SpecializationKey
            doc "Compile-unit identity. Same key = same compiled output."
            renderer: string
            text_backend: string
            params: Param*
            state: StateSlot*
            root: Node
        unique
        end

        record Component
            doc "Component."
            name: string
            params: Param*
            state: StateSlot*
            key: SpecializationKey
            root: Node
        end

        record Param
            doc "Param."
            name: string
            ty: Decl.ValueType
            slot: number
        end

        record StateSlot
            doc "StateSlot."
            name: string
            ty: Decl.ValueType
            slot: number
            initial: Value?
        end

        record Node
            doc "Node."
            local_id: number
            stable_id: ResolvedId
            visibility: Visibility
            layout: Layout
            decor: Decor
            clip: Clip?
            scroll: Scroll?
            scroll_control: ScrollControl?
            floating: Floating?
            input: Input
            aspect_ratio: Value?
            leaf: Leaf?
            children: Node*
        end

        record ResolvedId
            doc "ResolvedId."
            base: string
            salt: number
        end

        record Visibility
            doc "Visibility."
            visible_when: Value?
            enabled_when: Value?
        end

        record Layout
            doc "Layout."
            axis: Decl.Axis
            width: Size
            height: Size
            padding: Padding
            gap: Value
            align_x: Decl.AlignX
            align_y: Decl.AlignY
        end

        enum Size
            doc "Size."
            Fit { min: Value?, max: Value? }
            Grow { min: Value?, max: Value? }
            Fixed { value: Value }
            Percent { value: Value }
        end

        record Padding
            doc "Padding."
            left: Value
            top: Value
            right: Value
            bottom: Value
        end

        record Decor
            doc "Decor."
            background: Value?
            border: Border?
            radius: CornerRadius?
            opacity: Value?
        end

        record Border
            doc "Border."
            left: Value
            top: Value
            right: Value
            bottom: Value
            between_children: Value
            color: Value
        end

        record CornerRadius
            doc "CornerRadius."
            top_left: Value
            top_right: Value
            bottom_right: Value
            bottom_left: Value
        end

        record Clip
            doc "Clip."
            horizontal: boolean
            vertical: boolean
        end

        record Scroll
            doc "Scroll."
            horizontal: boolean
            vertical: boolean
        end

        record ScrollControl
            doc "ScrollControl."
            target: ResolvedId
            axis: Decl.ScrollAxis
            kind: Decl.ScrollControlKind
        end

        record Floating
            doc "Floating."
            target: FloatTarget
            element_point: Decl.AttachPoint
            parent_point: Decl.AttachPoint
            offset_x: Value
            offset_y: Value
            expand_w: Value
            expand_h: Value
            z_index: Value
            pointer_capture: Decl.PointerCapture
        end

        enum FloatTarget
            doc "FloatTarget."
            FloatParent
            FloatByStableId { id: ResolvedId }
        end

        record Input
            doc "Input."
            hover: boolean
            press: boolean
            focus: boolean
            wheel: boolean
            cursor: string?
            action: string?
        end

        enum Leaf
            doc "Leaf."
            Text { value: TextLeaf }
            Image { value: ImageLeaf }
            Custom { value: CustomLeaf }
        end

        record TextLeaf
            doc "TextLeaf."
            content: Value
            style: TextStyle
        end

        record TextStyle
            doc "TextStyle."
            color: Value
            font_id: Value
            font_size: Value
            letter_spacing: Value
            line_height: Value
            wrap: Decl.WrapMode
            align: Decl.TextAlign
        end

        record ImageLeaf
            doc "ImageLeaf."
            image_id: Value
            tint: Value
            fit: Decl.ImageFit
        end

        record CustomLeaf
            doc "CustomLeaf."
            kind: string
            payload: Value?
        end

        enum Value
            doc "Bound value: constants, slot references, or compound expressions."
            ConstBool { v: boolean }
            ConstNumber { v: number }
            ConstString { v: string }
            ConstColor { r: number, g: number, b: number, a: number }
            ConstVec2 { x: number, y: number }
            ParamSlot { slot: number }
            StateSlotRef { slot: number }
            EnvSlot { name: string }
            ScrollMetric { id: ResolvedId, metric: Decl.ScrollMetricKind }
            Unary { op: string, rhs: Value }
            Binary { op: string, lhs: Value, rhs: Value }
            Select { cond: Value, yes: Value, no: Value }
            Intrinsic { fn: string, args: Value* }
        end

        methods
            doc "Bound → Plan: flatten tree to indexed tables."
            Component:plan() -> Plan.Component
                doc "Flatten bound tree into indexed node table with side tables."
                status = "real"
                impl = require("src/plan")(types).boundary
                fallback = function(self, err)
                    return types.Plan.Component(self.key, List(), List(), List(), List(),
                        List(), List(), List(), List(), List(), List(), List(), 0)
                end
        end
    end

    -- ═══════════════════════════════════════════════════════
    phase Plan
    -- ═══════════════════════════════════════════════════════
        doc "Flat indexed tables. Ready for compilation."

        record Component
            doc "Planned component: flat node array + side tables."
            key: Bound.SpecializationKey
            nodes: Node*
            guards: Guard*
            paints: Paint*
            inputs: InputSpec*
            clips: ClipSpec*
            scrolls: ScrollSpec*
            scroll_controls: ScrollControlSpec*
            texts: TextSpec*
            images: ImageSpec*
            customs: CustomSpec*
            floats: FloatSpec*
            root_index: number
        unique
        end

        record Node
            doc "Node."
            index: number
            parent: number?
            first_child: number?
            child_count: number
            subtree_end: number
            axis: Decl.Axis
            width: SizeRule
            height: SizeRule
            padding_left: Binding
            padding_top: Binding
            padding_right: Binding
            padding_bottom: Binding
            gap: Binding
            align_x: Decl.AlignX
            align_y: Decl.AlignY
            guard_slot: number
            paint_slot: number
            input_slot: number
            clip_slot: number?
            scroll_slot: number?
            scroll_control_slot: number?
            text_slot: number?
            image_slot: number?
            custom_slot: number?
            float_slot: number?
            aspect_ratio: Binding?
        end

        enum SizeRule
            doc "SizeRule."
            Fit { min: Binding?, max: Binding? }
            Grow { min: Binding?, max: Binding? }
            Fixed { value: Binding }
            Percent { value: Binding }
        end

        record Guard
            doc "Guard."
            visible_when: Binding?
            enabled_when: Binding?
        end

        record Paint
            doc "Paint."
            background: Binding?
            border: Border?
            radius: CornerRadius?
            opacity: Binding?
        end

        record Border
            doc "Border."
            left: Binding
            top: Binding
            right: Binding
            bottom: Binding
            between_children: Binding
            color: Binding
        end

        record CornerRadius
            doc "CornerRadius."
            top_left: Binding
            top_right: Binding
            bottom_right: Binding
            bottom_left: Binding
        end

        record InputSpec
            doc "InputSpec."
            hover: boolean
            press: boolean
            focus: boolean
            wheel: boolean
            cursor: string?
            action: string?
        end

        record ClipSpec
            doc "ClipSpec."
            node_index: number
            horizontal: boolean
            vertical: boolean
        end

        record ScrollSpec
            doc "ScrollSpec."
            node_index: number
            horizontal: boolean
            vertical: boolean
        end

        record ScrollControlSpec
            doc "ScrollControlSpec."
            node_index: number
            target_node_index: number
            axis: Decl.ScrollAxis
            kind: Decl.ScrollControlKind
        end

        record TextSpec
            doc "TextSpec."
            node_index: number
            content: Binding
            color: Binding
            font_id: Binding
            font_size: Binding
            letter_spacing: Binding
            line_height: Binding
            wrap: Decl.WrapMode
            align: Decl.TextAlign
        end

        record ImageSpec
            doc "ImageSpec."
            node_index: number
            image_id: Binding
            tint: Binding
            fit: Decl.ImageFit
        end

        record CustomSpec
            doc "CustomSpec."
            node_index: number
            kind: string
            payload: Binding?
        end

        record FloatSpec
            doc "FloatSpec."
            node_index: number
            attach_parent_slot: number
            element_point: Decl.AttachPoint
            parent_point: Decl.AttachPoint
            offset_x: Binding
            offset_y: Binding
            expand_w: Binding
            expand_h: Binding
            z_index: Binding
            pointer_capture: Decl.PointerCapture
        end

        record LeafSlots
            doc "LeafSlots."
            text_slot: number?
            image_slot: number?
            custom_slot: number?
        end

        enum Binding
            doc "Planned binding: last sum type before Kernel eliminates all dispatch."
            ConstBool { v: boolean }
            ConstNumber { v: number }
            ConstString { v: string }
            ConstColor { r: number, g: number, b: number, a: number }
            ConstVec2 { x: number, y: number }
            Param { slot: number }
            State { slot: number }
            Env { name: string }
            ScrollMetric { node_index: number, metric: Decl.ScrollMetricKind }
            Expr { op: string, args: Binding* }
        end

        methods
            doc "Plan → Kernel: compile plan to { fn, state_t }."
            Component:compile(text_backend: TextBackend) -> Kernel.Component
                doc [[Compile plan into native code. Returns { fn = run_fn, state_t = frame_t }.
                    The frame_t layout is derived from this plan via __getentries.
                    The run_fn executes layout + hit_test + input + emit on &frame_t.]]
                status = "real"
                impl = require("src/compile")(types).boundary
                fallback = function(self, err)
                    local noop = terra(frame: &opaque) end
                    return types.Kernel.Component(self.key, terralib.types.newstruct("EmptyFrame"), `noop, `noop)
                end
        end
    end

    -- ═══════════════════════════════════════════════════════
    phase Kernel
    -- ═══════════════════════════════════════════════════════
        doc "Compiled output. Zero sum types. { fn, state_t } compile product."

        record Component
            doc [[The compile product.
                key:      specialization identity (memoize key).
                frame_t:  the state_t — runtime struct owning all per-frame data.
                init_fn:  terra(frame: &frame_t) — zero-initialize frame.
                run_fn:   terra(frame: &frame_t) — execute one frame.]]
            key: Bound.SpecializationKey
            frame_t: TerraType
            init_fn: TerraQuote
            run_fn: TerraQuote
        unique
        end

        methods
            doc "Kernel accessors."
            Component:frame_type() -> TerraType
                doc "The state_t: allocate with terralib.sizeof, pass &frame to run_fn."
                status = "real"
                impl = function(self) return self.frame_t end
            Component:run_quote() -> TerraQuote
                doc "The fn: terra(frame: &frame_t) executing one full frame."
                status = "real"
                impl = function(self) return self.run_fn end
        end
    end

    -- ═══════════════════════════════════════════════════════
    -- Exotype hooks: runtime Terra types with compile-time behavior.
    -- Installed on actual Terra structs via TerraUI:install_hooks({...}).
    -- ═══════════════════════════════════════════════════════

    hooks Frame
        doc "Runtime frame struct. Layout derived from Plan.Component via __getentries."
        getentries
            doc "Derive struct fields from the associated plan."
            impl = function(self) error("Frame:__getentries must be installed via install_hooks") end
        staticinitialize
            doc "Install init/run methods after layout is known."
            impl = function(self) end
    end

    hooks Color
        doc "RGBA color with component-wise arithmetic for quote composition."
        add
            doc "Component-wise addition."
            impl = terra(a: Color, b: Color) : Color
                return Color { a.r+b.r, a.g+b.g, a.b+b.b, a.a+b.a }
            end
        sub
            doc "Component-wise subtraction."
            impl = terra(a: Color, b: Color) : Color
                return Color { a.r-b.r, a.g-b.g, a.b-b.b, a.a-b.a }
            end
        mul
            doc "Scalar multiply."
            impl = terra(a: Color, b: float) : Color
                return Color { a.r*b, a.g*b, a.b*b, a.a*b }
            end
    end

    hooks Vec2
        doc "2D vector with component-wise arithmetic."
        add
            doc "Component-wise add."
            impl = terra(a: Vec2, b: Vec2) : Vec2
                return Vec2 { a.x+b.x, a.y+b.y }
            end
        sub
            doc "Component-wise sub."
            impl = terra(a: Vec2, b: Vec2) : Vec2
                return Vec2 { a.x-b.x, a.y-b.y }
            end
        mul
            doc "Scalar multiply."
            impl = terra(a: Vec2, b: float) : Vec2
                return Vec2 { a.x*b, a.y*b }
            end
    end
end

return TerraUI
