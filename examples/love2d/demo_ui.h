#ifndef DEMO_UI_H
#define DEMO_UI_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>

typedef struct TerraUI_Color { float r, g, b, a; } TerraUI_Color;
typedef struct TerraUI_Vec2  { float x, y; } TerraUI_Vec2;

typedef struct TerraUI_NodeState {
    float x, y, w, h;
    float content_x, content_y, content_w, content_h;
    float content_extent_w, content_extent_h;
    float scroll_x, scroll_y;
    bool scroll_need_x, scroll_need_y;
    float want_w, want_h;
    float clip_x0, clip_y0, clip_x1, clip_y1;
    bool visible;
    bool enabled;
} TerraUI_NodeState;

typedef struct TerraUI_InputState {
    float mouse_x, mouse_y;
    bool mouse_down, mouse_pressed, mouse_released;
    float wheel_dx, wheel_dy;
} TerraUI_InputState;

typedef struct TerraUI_HitState {
    int32_t hot, active, focus;
    float active_offset_x, active_offset_y;
} TerraUI_HitState;

typedef struct TerraUI_RectCmd {
    float x, y, w, h;
    TerraUI_Color color;
    float opacity;
    float z;
    uint32_t seq;
} TerraUI_RectCmd;

typedef struct TerraUI_BorderCmd {
    float x, y, w, h;
    float left, top, right, bottom;
    TerraUI_Color color;
    float opacity;
    float z;
    uint32_t seq;
} TerraUI_BorderCmd;

typedef struct TerraUI_TextCmd {
    float x, y, w, h;
    const char *text;
    const char *font_id;
    float font_size;
    float letter_spacing;
    float line_height;
    int32_t wrap;
    int32_t align;
    TerraUI_Color color;
    float z;
    uint32_t seq;
} TerraUI_TextCmd;

typedef struct TerraUI_ImageCmd {
    float x, y, w, h;
    const char *image_id;
    TerraUI_Color tint;
    float z;
    uint32_t seq;
} TerraUI_ImageCmd;

typedef struct TerraUI_ScissorCmd {
    bool is_begin;
    float x0, y0, x1, y1;
    float z;
    uint32_t seq;
} TerraUI_ScissorCmd;

typedef struct TerraUI_CustomCmd {
    float x, y, w, h;
    const char *kind;
    float z;
    uint32_t seq;
} TerraUI_CustomCmd;

typedef struct demo_ui_Params {
    const char * p0; /* selected_tool */
    const char * p1; /* selected_asset */
    const char * p2; /* status_primary */
    const char * p3; /* status_secondary */
    const char * p4; /* hint_text */
    const char * p5; /* preview_image */
    const char * p6; /* preview_title */
    const char * p7; /* detail_a */
    const char * p8; /* detail_b */
    const char * p9; /* footer_text */
    float p10; /* progress_a */
    float p11; /* progress_b */
    TerraUI_Color p12; /* accent */
    const char * p13; /* mode_summary */
    const char * p14; /* mode_line_1 */
    const char * p15; /* mode_line_2 */
    const char * p16; /* mode_line_3 */
    const char * p17; /* asset_meta_1 */
    const char * p18; /* asset_meta_2 */
    const char * p19; /* asset_meta_3 */
    const char * p20; /* event_1 */
    const char * p21; /* event_2 */
    const char * p22; /* event_3 */
} demo_ui_Params;

typedef struct demo_ui_State {
    float s0; /* app/toolbar/gap */
    float s1; /* app/preview_card/gap */
    float s2; /* app/preview_card/bottom/meta_col/tool_row/gap */
    float s3; /* app/preview_card/bottom/meta_col/selection_row/gap */
    float s4; /* app/preview_card/bottom/meta_col/mode_row/gap */
    float s5; /* app/preview_card/bottom/meta_col/state_row/gap */
    float s6; /* app/preview_card/bottom/meter_col/coverage_meter/gap */
    float s7; /* app/preview_card/bottom/meter_col/bake_meter/gap */
    float s8; /* app/main/center/activity/gap */
    float s9; /* app/main/inspector/gap */
    float s10; /* inspector/asset_info/gap */
    float s11; /* inspector/tool_info/gap */
    float s12; /* inspector/target_info/gap */
    float s13; /* app/footer/gap */
} demo_ui_State;

typedef struct demo_ui_Frame {
    demo_ui_Params params;
    demo_ui_State state;
    TerraUI_NodeState nodes[111];
    TerraUI_InputState input;
    TerraUI_HitState hit;
    void *text_backend_state;
    float viewport_w;
    float viewport_h;
    uint32_t draw_seq;
    int32_t action_node;
    const char *action_name;
    const char *cursor_name;
    TerraUI_RectCmd rects[25];
    int32_t rect_count;
    TerraUI_BorderCmd borders[21];
    int32_t border_count;
    TerraUI_TextCmd texts[64];
    int32_t text_count;
    TerraUI_ImageCmd images[1];
    int32_t image_count;
    TerraUI_ScissorCmd scissors[2];
    int32_t scissor_count;
    TerraUI_CustomCmd customs[4];
    int32_t custom_count;
} demo_ui_Frame;

void demo_ui_init(demo_ui_Frame *frame);
void demo_ui_run(demo_ui_Frame *frame);

/* node_count = 111 */

/* Param slots:
 *   p0 = selected_tool (const char *)
 *   p1 = selected_asset (const char *)
 *   p2 = status_primary (const char *)
 *   p3 = status_secondary (const char *)
 *   p4 = hint_text (const char *)
 *   p5 = preview_image (const char *)
 *   p6 = preview_title (const char *)
 *   p7 = detail_a (const char *)
 *   p8 = detail_b (const char *)
 *   p9 = footer_text (const char *)
 *   p10 = progress_a (float)
 *   p11 = progress_b (float)
 *   p12 = accent (TerraUI_Color)
 *   p13 = mode_summary (const char *)
 *   p14 = mode_line_1 (const char *)
 *   p15 = mode_line_2 (const char *)
 *   p16 = mode_line_3 (const char *)
 *   p17 = asset_meta_1 (const char *)
 *   p18 = asset_meta_2 (const char *)
 *   p19 = asset_meta_3 (const char *)
 *   p20 = event_1 (const char *)
 *   p21 = event_2 (const char *)
 *   p22 = event_3 (const char *)
 */

#ifdef __cplusplus
}
#endif

#endif /* DEMO_UI_H */
