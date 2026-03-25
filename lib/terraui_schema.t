import "lib/schema"

local function is_bind_ctx(v)
    return type(v) == "table"
end

local function is_plan_ctx(v)
    return type(v) == "table"
end

local function is_compile_ctx(v)
    return type(v) == "table"
end

-- NOTE:
-- This is the runtime-loadable Terra schema source for TerraUI.
-- It is very close to docs/design/terraui.asdl, but uses a couple of
-- stock-ASDL-safe names where raw constructor/type namespace collisions would
-- otherwise occur.

local schema TerraUI
    extern TerraType = terralib.types.istype
    extern TerraQuote = terralib.isquote
    extern BindCtx = is_bind_ctx
    extern PlanCtx = is_plan_ctx
    extern CompileCtx = is_compile_ctx

    phase Decl
        record Component
            name: string
            params: Param*
            state: StateSlot*
            themes: ThemeDef*
            widgets: WidgetDef*
            root: Node
        unique
        end

        record Param
            name: string
            ty: ValueType
            default: Expr?
        end

        record StateSlot
            name: string
            ty: ValueType
            initial: Expr?
        end

        flags ValueType
            TBool
            TNumber
            TString
            TColor
            TImage
            TVec2
            TAny
        end

        record ThemeDef
            name: string
            parent: string?
            tokens: ThemeToken*
        end

        record ThemeToken
            name: string
            ty: ValueType
            value: Expr
        end

        record ThemeOverride
            name: string
            value: Expr
        end

        record ThemeScope
            base_theme: string?
            overrides: ThemeOverride*
        end

        record WidgetDef
            name: string
            props: WidgetProp*
            state: StateSlot*
            slots: WidgetSlot*
            parts: WidgetPart*
            root: Node
        end

        record WidgetProp
            name: string
            ty: ValueType
            default: Expr?
        end

        record WidgetSlot
            name: string
        end

        record WidgetPart
            name: string
        end

        record StylePatch
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
        end

        enum Id
            Auto
            Stable { name: string }
            Indexed { name: string, index: Expr }
        end

        enum Child
            NodeChild { value: Node }
            WidgetChild { value: WidgetCall }
            SlotRef { name: string }
        end

        record WidgetCall
            id: Id?
            name: string
            props: PropArg*
            styles: PartStyleArg*
            slots: SlotArg*
        end

        record PropArg
            name: string
            value: Expr
        end

        record PartStyleArg
            name: string
            patch: StylePatch
        end

        record SlotArg
            name: string
            children: Child*
        end

        record Visibility
            visible_when: Expr?
            enabled_when: Expr?
        end

        record Layout
            axis: Axis
            width: Size
            height: Size
            padding: Padding
            gap: Expr
            align_x: AlignX
            align_y: AlignY
        end

        flags Axis
            Row
            Column
            Stack
        end

        flags AlignX
            AlignLeft
            AlignCenterX
            AlignRight
        end

        flags AlignY
            AlignTop
            AlignCenterY
            AlignBottom
        end

        enum Size
            Fit { min: Expr?, max: Expr? }
            Grow { min: Expr?, max: Expr? }
            Fixed { value: Expr }
            Percent { value: Expr }
        end

        record Padding
            left: Expr
            top: Expr
            right: Expr
            bottom: Expr
        end

        record Decor
            background: Expr?
            border: Border?
            radius: CornerRadius?
            opacity: Expr?
        end

        record Border
            left: Expr
            top: Expr
            right: Expr
            bottom: Expr
            between_children: Expr
            color: Expr
        end

        record CornerRadius
            top_left: Expr
            top_right: Expr
            bottom_right: Expr
            bottom_left: Expr
        end

        record Clip
            horizontal: boolean
            vertical: boolean
        end

        record Scroll
            horizontal: boolean
            vertical: boolean
        end

        flags ScrollAxis
            ScrollAxisX
            ScrollAxisY
        end

        flags ScrollMetricKind
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
            ScrollThumbKind
            ScrollPageDecKind
            ScrollPageIncKind
        end

        record ScrollControl
            target: Id
            axis: ScrollAxis
            kind: ScrollControlKind
        end

        record Floating
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
            FloatParent
            FloatById { id: Id }
        end

        flags AttachPoint
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
            Capture
            Passthrough
        end

        record Input
            hover: boolean
            press: boolean
            focus: boolean
            wheel: boolean
            cursor: string?
            action: string?
        end

        enum Leaf
            Text { value: TextLeaf }
            Image { value: ImageLeaf }
            Custom { value: CustomLeaf }
        end

        record TextLeaf
            content: Expr
            style: TextStyle
        end

        record TextStyle
            color: Expr
            font_id: Expr
            font_size: Expr
            letter_spacing: Expr
            line_height: Expr
            wrap: WrapMode
            align: TextAlign
        end

        flags WrapMode
            WrapWords
            WrapNewlines
            WrapNone
        end

        flags TextAlign
            TextAlignLeft
            TextAlignCenter
            TextAlignRight
        end

        record ImageLeaf
            image_id: Expr
            tint: Expr
            fit: ImageFit
        end

        flags ImageFit
            ImageStretch
            ImageContain
            ImageCover
        end

        record CustomLeaf
            kind: string
            payload: Expr?
        end

        enum Expr
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
            Component:bind(ctx: BindCtx) -> Bound.Component
            Param:bind(ctx: BindCtx) -> Bound.Param
            StateSlot:bind(ctx: BindCtx) -> Bound.StateSlot
            Node:bind(ctx: BindCtx) -> Bound.Node
            Visibility:bind(ctx: BindCtx) -> Bound.Visibility
            Layout:bind(ctx: BindCtx) -> Bound.Layout
            Size:bind(ctx: BindCtx) -> Bound.Size
            Padding:bind(ctx: BindCtx) -> Bound.Padding
            Decor:bind(ctx: BindCtx) -> Bound.Decor
            Border:bind(ctx: BindCtx) -> Bound.Border
            CornerRadius:bind(ctx: BindCtx) -> Bound.CornerRadius
            Clip:bind(ctx: BindCtx) -> Bound.Clip
            Scroll:bind(ctx: BindCtx) -> Bound.Scroll
            ScrollControl:bind(ctx: BindCtx) -> Bound.ScrollControl
            Floating:bind(ctx: BindCtx) -> Bound.Floating
            Input:bind(ctx: BindCtx) -> Bound.Input
            Leaf:bind(ctx: BindCtx) -> Bound.Leaf
            TextLeaf:bind(ctx: BindCtx) -> Bound.TextLeaf
            TextStyle:bind(ctx: BindCtx) -> Bound.TextStyle
            ImageLeaf:bind(ctx: BindCtx) -> Bound.ImageLeaf
            CustomLeaf:bind(ctx: BindCtx) -> Bound.CustomLeaf
            Expr:bind(ctx: BindCtx) -> Bound.Value
        end
    end

    phase Bound
        record SpecializationKey
            renderer: string
            text_backend: string
            params: Param*
            state: StateSlot*
            root: Node
        unique
        end

        record Component
            name: string
            params: Param*
            state: StateSlot*
            key: SpecializationKey
            root: Node
        end

        record Param
            name: string
            ty: Decl.ValueType
            slot: number
        end

        record StateSlot
            name: string
            ty: Decl.ValueType
            slot: number
            initial: Value?
        end

        record Node
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
            base: string
            salt: number
        end

        record Visibility
            visible_when: Value?
            enabled_when: Value?
        end

        record Layout
            axis: Decl.Axis
            width: Size
            height: Size
            padding: Padding
            gap: Value
            align_x: Decl.AlignX
            align_y: Decl.AlignY
        end

        enum Size
            Fit { min: Value?, max: Value? }
            Grow { min: Value?, max: Value? }
            Fixed { value: Value }
            Percent { value: Value }
        end

        record Padding
            left: Value
            top: Value
            right: Value
            bottom: Value
        end

        record Decor
            background: Value?
            border: Border?
            radius: CornerRadius?
            opacity: Value?
        end

        record Border
            left: Value
            top: Value
            right: Value
            bottom: Value
            between_children: Value
            color: Value
        end

        record CornerRadius
            top_left: Value
            top_right: Value
            bottom_right: Value
            bottom_left: Value
        end

        record Clip
            horizontal: boolean
            vertical: boolean
        end

        record Scroll
            horizontal: boolean
            vertical: boolean
        end

        record ScrollControl
            target: ResolvedId
            axis: Decl.ScrollAxis
            kind: Decl.ScrollControlKind
        end

        record Floating
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
            FloatParent
            FloatByStableId { id: ResolvedId }
        end

        record Input
            hover: boolean
            press: boolean
            focus: boolean
            wheel: boolean
            cursor: string?
            action: string?
        end

        enum Leaf
            Text { value: TextLeaf }
            Image { value: ImageLeaf }
            Custom { value: CustomLeaf }
        end

        record TextLeaf
            content: Value
            style: TextStyle
        end

        record TextStyle
            color: Value
            font_id: Value
            font_size: Value
            letter_spacing: Value
            line_height: Value
            wrap: Decl.WrapMode
            align: Decl.TextAlign
        end

        record ImageLeaf
            image_id: Value
            tint: Value
            fit: Decl.ImageFit
        end

        record CustomLeaf
            kind: string
            payload: Value?
        end

        enum Value
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
            Component:plan(ctx: PlanCtx) -> Plan.Component
            Node:plan(ctx: PlanCtx, parent_index: number) -> number
            Size:plan(ctx: PlanCtx) -> Plan.SizeRule
            Clip:plan(ctx: PlanCtx, node_index: number) -> number
            Scroll:plan(ctx: PlanCtx, node_index: number) -> number
            ScrollControl:plan(ctx: PlanCtx, node_index: number) -> number
            Leaf:plan(ctx: PlanCtx, node_index: number) -> Plan.LeafSlots
            Value:plan_binding(ctx: PlanCtx) -> Plan.Binding
        end
    end

    phase Plan
        record Component
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
            Fit { min: Binding?, max: Binding? }
            Grow { min: Binding?, max: Binding? }
            Fixed { value: Binding }
            Percent { value: Binding }
        end

        record Guard
            visible_when: Binding?
            enabled_when: Binding?
        end

        record Paint
            background: Binding?
            border: Border?
            radius: CornerRadius?
            opacity: Binding?
        end

        record Border
            left: Binding
            top: Binding
            right: Binding
            bottom: Binding
            between_children: Binding
            color: Binding
        end

        record CornerRadius
            top_left: Binding
            top_right: Binding
            bottom_right: Binding
            bottom_left: Binding
        end

        record InputSpec
            hover: boolean
            press: boolean
            focus: boolean
            wheel: boolean
            cursor: string?
            action: string?
        end

        record ClipSpec
            node_index: number
            horizontal: boolean
            vertical: boolean
        end

        record ScrollSpec
            node_index: number
            horizontal: boolean
            vertical: boolean
        end

        record ScrollControlSpec
            node_index: number
            target_node_index: number
            axis: Decl.ScrollAxis
            kind: Decl.ScrollControlKind
        end

        record TextSpec
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
            node_index: number
            image_id: Binding
            tint: Binding
            fit: Decl.ImageFit
        end

        record CustomSpec
            node_index: number
            kind: string
            payload: Binding?
        end

        record FloatSpec
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
            text_slot: number?
            image_slot: number?
            custom_slot: number?
        end

        enum Binding
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
            Component:compile(ctx: CompileCtx) -> Kernel.Component
            Node:compile_layout(ctx: CompileCtx) -> TerraQuote
            Node:compile_hit(ctx: CompileCtx) -> TerraQuote
            SizeRule:compile_axis(ctx: CompileCtx, axis_name: string) -> TerraQuote
            Paint:compile_emit(ctx: CompileCtx, node_index: number) -> TerraQuote
            InputSpec:compile_input(ctx: CompileCtx, node_index: number) -> TerraQuote
            ClipSpec:compile_apply(ctx: CompileCtx) -> TerraQuote
            ClipSpec:compile_emit_begin(ctx: CompileCtx) -> TerraQuote
            ClipSpec:compile_emit_end(ctx: CompileCtx) -> TerraQuote
            ScrollSpec:compile_apply(ctx: CompileCtx) -> TerraQuote
            ScrollSpec:compile_input(ctx: CompileCtx) -> TerraQuote
            ScrollControlSpec:compile_input(ctx: CompileCtx) -> TerraQuote
            TextSpec:compile_measure_width(ctx: CompileCtx) -> TerraQuote
            TextSpec:compile_measure_height_for_width(ctx: CompileCtx, max_width: TerraQuote) -> TerraQuote
            TextSpec:compile_emit(ctx: CompileCtx) -> TerraQuote
            ImageSpec:compile_emit(ctx: CompileCtx) -> TerraQuote
            CustomSpec:compile_emit(ctx: CompileCtx) -> TerraQuote
            FloatSpec:compile_place(ctx: CompileCtx) -> TerraQuote
            Binding:compile_bool(ctx: CompileCtx) -> TerraQuote
            Binding:compile_number(ctx: CompileCtx) -> TerraQuote
            Binding:compile_string(ctx: CompileCtx) -> TerraQuote
            Binding:compile_color(ctx: CompileCtx) -> TerraQuote
            Binding:compile_vec2(ctx: CompileCtx) -> TerraQuote
        end
    end

    phase Kernel
        record RectStream
            cmd_t: TerraType
            emit_fn: TerraQuote
        end

        record BorderStream
            cmd_t: TerraType
            emit_fn: TerraQuote
        end

        record TextStream
            cmd_t: TerraType
            measure_fn: TerraQuote
            emit_fn: TerraQuote
        end

        record ImageStream
            cmd_t: TerraType
            emit_fn: TerraQuote
        end

        record ScissorStream
            cmd_t: TerraType
            emit_fn: TerraQuote
        end

        record CustomStream
            cmd_t: TerraType
            emit_fn: TerraQuote
        end

        record RuntimeTypes
            params_t: TerraType
            state_t: TerraType
            frame_t: TerraType
            input_t: TerraType
            node_t: TerraType
            clip_state_t: TerraType
            scroll_state_t: TerraType
            hit_t: TerraType
        end

        record Kernels
            init_fn: TerraQuote
            layout_fn: TerraQuote
            input_fn: TerraQuote
            hit_test_fn: TerraQuote
            run_fn: TerraQuote
        end

        record Component
            key: Bound.SpecializationKey
            types: RuntimeTypes
            rects: RectStream
            borders: BorderStream
            texts: TextStream
            images: ImageStream
            scissors: ScissorStream
            customs: CustomStream
            kernels: Kernels
        unique
        end

        methods
            Component:frame_type() -> TerraType
            Component:run_quote() -> TerraQuote
        end
    end
end

return TerraUI
