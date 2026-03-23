#define CLAY_IMPLEMENTATION
#include "clay.h"
#include "bench/clay_bench.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct ClayBenchContext {
    void *memory;
    int capacity_elements;
    Clay_Context *ctx;
} ClayBenchContext;

static ClayBenchContext clay_bench_ctx = {0};
static int clay_bench_had_error = 0;
static void *clay_dummy_image = (void*)0x1;

static void ClayBench_Error(Clay_ErrorData errorData) {
    clay_bench_had_error = 1;
    fprintf(stderr, "clay error: %.*s\n", errorData.errorText.length, errorData.errorText.chars);
}

static Clay_Dimensions ClayBench_MeasureText(Clay_StringSlice text, Clay_TextElementConfig *config, void *userData) {
    (void)userData;
    float line_height = config->lineHeight > 0 ? (float)config->lineHeight : (float)config->fontSize * 1.2f;
    return (Clay_Dimensions) {
        .width = (float)text.length * (float)config->fontSize * 0.6f,
        .height = line_height,
    };
}

static Clay_Color clay_rgba(float r, float g, float b, float a) {
    return (Clay_Color) { r * 255.0f, g * 255.0f, b * 255.0f, a * 255.0f };
}

static Clay_String clay_cstr(const char *s) {
    return (Clay_String) { .isStaticallyAllocated = false, .length = (int32_t)strlen(s), .chars = s };
}

static Clay_TextElementConfig *ClayBench_TextConfig(uint16_t font_size, Clay_Color color) {
    return CLAY_TEXT_CONFIG({ .fontSize = font_size, .lineHeight = (uint16_t)(font_size * 1.2f), .textColor = color, .wrapMode = CLAY_TEXT_WRAP_NONE, .textAlignment = CLAY_TEXT_ALIGN_LEFT });
}

static void ClayBench_EnsureContext(int max_elements, int viewport_w, int viewport_h) {
    if (clay_bench_ctx.ctx && clay_bench_ctx.capacity_elements >= max_elements) {
        Clay_SetCurrentContext(clay_bench_ctx.ctx);
        Clay_SetLayoutDimensions((Clay_Dimensions) { (float)viewport_w, (float)viewport_h });
        return;
    }

    if (clay_bench_ctx.memory) {
        free(clay_bench_ctx.memory);
        clay_bench_ctx.memory = NULL;
        clay_bench_ctx.ctx = NULL;
        clay_bench_ctx.capacity_elements = 0;
    }

    Clay_SetMaxElementCount(max_elements);
    Clay_SetMaxMeasureTextCacheWordCount(max_elements * 8);

    uint32_t min_memory = Clay_MinMemorySize();
    clay_bench_ctx.memory = malloc(min_memory);
    Clay_Arena arena = Clay_CreateArenaWithCapacityAndMemory(min_memory, clay_bench_ctx.memory);
    clay_bench_ctx.ctx = Clay_Initialize(arena, (Clay_Dimensions) { (float)viewport_w, (float)viewport_h }, (Clay_ErrorHandler) { ClayBench_Error, NULL });
    Clay_SetMeasureTextFunction(ClayBench_MeasureText, NULL);
    Clay_SetCullingEnabled(false);
    clay_bench_ctx.capacity_elements = max_elements;
}

static void ClayBench_FillStats(Clay_RenderCommandArray cmds, int element_count, ClayBenchStats *out_stats) {
    ClayBenchStats stats = {0};
    stats.had_error = clay_bench_had_error;
    if (!clay_bench_had_error) {
        stats.element_count = element_count;
        stats.command_count = cmds.length;
        for (int i = 0; i < cmds.length; ++i) {
            switch (cmds.internalArray[i].commandType) {
                case CLAY_RENDER_COMMAND_TYPE_RECTANGLE: stats.rect_count++; break;
                case CLAY_RENDER_COMMAND_TYPE_BORDER: stats.border_count++; break;
                case CLAY_RENDER_COMMAND_TYPE_TEXT: stats.text_count++; break;
                case CLAY_RENDER_COMMAND_TYPE_IMAGE: stats.image_count++; break;
                case CLAY_RENDER_COMMAND_TYPE_SCISSOR_START:
                case CLAY_RENDER_COMMAND_TYPE_SCISSOR_END: stats.scissor_count++; break;
                case CLAY_RENDER_COMMAND_TYPE_CUSTOM: stats.custom_count++; break;
                default: break;
            }
        }
    }
    *out_stats = stats;
}

void ClayBench_BuildFlatList(int item_count, int viewport_w, int viewport_h, ClayBenchStats *out_stats) {
    ClayBench_EnsureContext(item_count * 20 + 1024, viewport_w, viewport_h);
    clay_bench_had_error = 0;
    Clay_SetPointerState((Clay_Vector2) { -10000, -10000 }, false);
    Clay_BeginLayout();

    CLAY(CLAY_ID("root"), {
        .layout = { .layoutDirection = CLAY_TOP_TO_BOTTOM, .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_GROW(0) }, .padding = CLAY_PADDING_ALL(8), .childGap = 2 },
        .backgroundColor = clay_rgba(0.08f, 0.09f, 0.11f, 1),
    }) {
        for (int i = 0; i < item_count; ++i) {
            char name_buf[64];
            char tag_buf[32];
            snprintf(name_buf, sizeof(name_buf), "Row %d", i);
            snprintf(tag_buf, sizeof(tag_buf), "Tag %d", i % 16);
            CLAY(CLAY_SIDI(CLAY_STRING("row"), i), {
                .layout = { .layoutDirection = CLAY_LEFT_TO_RIGHT, .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_FIT(0) }, .padding = CLAY_PADDING_ALL(6), .childGap = 8, .childAlignment = { .y = CLAY_ALIGN_Y_CENTER } },
                .backgroundColor = (i % 2 == 0) ? clay_rgba(0.14f, 0.15f, 0.18f, 1) : clay_rgba(0.12f, 0.13f, 0.16f, 1),
                .border = { .color = clay_rgba(0.22f, 0.24f, 0.28f, 1), .width = {0, 0, 0, 1, 0} },
            }) {
                CLAY_AUTO_ID({ .layout = { .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_FIT(0) } } }) {
                    CLAY_TEXT(clay_cstr(name_buf), ClayBench_TextConfig(15, clay_rgba(0.92f, 0.93f, 0.95f, 1)));
                }
                CLAY_AUTO_ID({ .layout = { .padding = CLAY_PADDING_ALL(4), .sizing = { .width = CLAY_SIZING_FIT(0), .height = CLAY_SIZING_FIT(0) } }, .backgroundColor = clay_rgba(0.17f, 0.24f, 0.34f, 1), .border = { .color = clay_rgba(0.28f, 0.38f, 0.56f, 1), .width = CLAY_BORDER_OUTSIDE(1) } }) {
                    CLAY_TEXT(clay_cstr(tag_buf), ClayBench_TextConfig(13, clay_rgba(0.86f, 0.92f, 1.0f, 1)));
                }
            }
        }
    }

    Clay_RenderCommandArray cmds = Clay_EndLayout();
    ClayBench_FillStats(cmds, Clay_GetCurrentContext()->layoutElements.length, out_stats);
}

void ClayBench_BuildTextHeavy(int item_count, int viewport_w, int viewport_h, ClayBenchStats *out_stats) {
    ClayBench_EnsureContext(item_count * 8 + 512, viewport_w, viewport_h);
    clay_bench_had_error = 0;
    Clay_SetPointerState((Clay_Vector2) { -10000, -10000 }, false);
    Clay_BeginLayout();

    CLAY(CLAY_ID("root"), {
        .layout = { .layoutDirection = CLAY_TOP_TO_BOTTOM, .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_GROW(0) }, .padding = CLAY_PADDING_ALL(10), .childGap = 4 },
        .backgroundColor = clay_rgba(0.10f, 0.11f, 0.14f, 1),
    }) {
        for (int i = 0; i < item_count; ++i) {
            char text_buf[128];
            snprintf(text_buf, sizeof(text_buf), "Text row %d with a modest amount of content for measurement.", i);
            CLAY(CLAY_SIDI(CLAY_STRING("textrow"), i), {
                .layout = { .padding = CLAY_PADDING_ALL(4), .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_FIT(0) } },
            }) {
                CLAY_TEXT(clay_cstr(text_buf), ClayBench_TextConfig(15, clay_rgba(0.92f, 0.93f, 0.95f, 1)));
            }
        }
    }

    Clay_RenderCommandArray cmds = Clay_EndLayout();
    ClayBench_FillStats(cmds, Clay_GetCurrentContext()->layoutElements.length, out_stats);
}

void ClayBench_BuildNestedPanels(int group_count, int viewport_w, int viewport_h, ClayBenchStats *out_stats) {
    ClayBench_EnsureContext(group_count * 18 + 512, viewport_w, viewport_h);
    clay_bench_had_error = 0;
    Clay_SetPointerState((Clay_Vector2) { -10000, -10000 }, false);
    Clay_BeginLayout();

    CLAY(CLAY_ID("root"), {
        .layout = { .layoutDirection = CLAY_LEFT_TO_RIGHT, .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_GROW(0) }, .padding = CLAY_PADDING_ALL(8), .childGap = 8 },
        .backgroundColor = clay_rgba(0.08f, 0.09f, 0.11f, 1),
    }) {
        for (int g = 0; g < group_count; ++g) {
            CLAY(CLAY_SIDI(CLAY_STRING("group"), g), {
                .layout = { .layoutDirection = CLAY_TOP_TO_BOTTOM, .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_GROW(0) }, .padding = CLAY_PADDING_ALL(8), .childGap = 6 },
                .backgroundColor = clay_rgba(0.12f, 0.13f, 0.15f, 1),
                .border = { .color = clay_rgba(0.22f, 0.24f, 0.28f, 1), .width = CLAY_BORDER_OUTSIDE(1) },
            }) {
                for (int i = 0; i < 6; ++i) {
                    char title_buf[32];
                    snprintf(title_buf, sizeof(title_buf), "Card %d.%d", g, i);
                    CLAY_AUTO_ID({ .layout = { .layoutDirection = CLAY_TOP_TO_BOTTOM, .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_FIT(0) }, .padding = CLAY_PADDING_ALL(6), .childGap = 4 }, .backgroundColor = clay_rgba(0.16f, 0.18f, 0.23f, 1), .border = { .color = clay_rgba(0.28f, 0.30f, 0.36f, 1), .width = CLAY_BORDER_OUTSIDE(1) } }) {
                        CLAY_TEXT(clay_cstr(title_buf), ClayBench_TextConfig(15, clay_rgba(0.96f, 0.97f, 0.98f, 1)));
                        CLAY_TEXT(CLAY_STRING("Nested panel content"), ClayBench_TextConfig(13, clay_rgba(0.70f, 0.74f, 0.80f, 1)));
                    }
                }
            }
        }
    }

    Clay_RenderCommandArray cmds = Clay_EndLayout();
    ClayBench_FillStats(cmds, Clay_GetCurrentContext()->layoutElements.length, out_stats);
}

void ClayBench_BuildInspectorMini(int item_count, int viewport_w, int viewport_h, ClayBenchStats *out_stats) {
    ClayBench_EnsureContext(item_count * 24 + 2048, viewport_w, viewport_h);
    clay_bench_had_error = 0;
    Clay_SetPointerState((Clay_Vector2) { -10000, -10000 }, false);
    Clay_BeginLayout();

    CLAY(CLAY_ID("root"), {
        .layout = { .layoutDirection = CLAY_TOP_TO_BOTTOM, .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_GROW(0) }, .padding = CLAY_PADDING_ALL(10), .childGap = 10 },
        .backgroundColor = clay_rgba(0.08f, 0.09f, 0.11f, 1),
    }) {
        CLAY(CLAY_ID("toolbar"), {
            .layout = { .layoutDirection = CLAY_LEFT_TO_RIGHT, .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_FIXED(40) }, .padding = CLAY_PADDING_ALL(6), .childGap = 6, .childAlignment = { .y = CLAY_ALIGN_Y_CENTER } },
            .backgroundColor = clay_rgba(0.10f, 0.11f, 0.14f, 1),
            .border = { .color = clay_rgba(0.22f, 0.24f, 0.28f, 1), .width = {0, 0, 0, 1, 0} },
        }) {
            for (int i = 0; i < 3; ++i) {
                char buf[16]; snprintf(buf, sizeof(buf), "Tab %d", i);
                CLAY_AUTO_ID({ .layout = { .padding = CLAY_PADDING_ALL(6), .sizing = { .width = CLAY_SIZING_FIT(0), .height = CLAY_SIZING_FIT(0) } }, .backgroundColor = clay_rgba(0.18f, 0.24f, 0.36f, 1), .border = { .color = clay_rgba(0.28f, 0.38f, 0.56f, 1), .width = CLAY_BORDER_OUTSIDE(1) } }) {
                    CLAY_TEXT(clay_cstr(buf), ClayBench_TextConfig(14, clay_rgba(1,1,1,1)));
                }
            }
        }

        CLAY(CLAY_ID("main"), { .layout = { .layoutDirection = CLAY_LEFT_TO_RIGHT, .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_GROW(0) }, .childGap = 10 } }) {
            CLAY(CLAY_ID("assets"), {
                .layout = { .layoutDirection = CLAY_TOP_TO_BOTTOM, .sizing = { .width = CLAY_SIZING_FIXED(260), .height = CLAY_SIZING_GROW(0) }, .padding = CLAY_PADDING_ALL(8), .childGap = 4 },
                .backgroundColor = clay_rgba(0.12f, 0.13f, 0.15f, 1),
                .border = { .color = clay_rgba(0.22f, 0.24f, 0.28f, 1), .width = CLAY_BORDER_OUTSIDE(1) },
            }) {
                CLAY_TEXT(CLAY_STRING("Assets"), ClayBench_TextConfig(18, clay_rgba(0.96f, 0.97f, 0.98f, 1)));
                for (int i = 0; i < item_count; ++i) {
                    char buf[32]; snprintf(buf, sizeof(buf), "Asset %d", i);
                    CLAY(CLAY_SIDI(CLAY_STRING("asset"), i), { .layout = { .padding = CLAY_PADDING_ALL(5), .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_FIT(0) } }, .backgroundColor = (i % 2 == 0) ? clay_rgba(0.14f, 0.15f, 0.18f, 1) : clay_rgba(0.12f, 0.13f, 0.16f, 1) }) {
                        CLAY_TEXT(clay_cstr(buf), ClayBench_TextConfig(14, clay_rgba(0.92f, 0.93f, 0.95f, 1)));
                    }
                }
            }

            CLAY(CLAY_ID("center"), { .layout = { .layoutDirection = CLAY_TOP_TO_BOTTOM, .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_GROW(0) }, .childGap = 8 } }) {
                CLAY_TEXT(CLAY_STRING("Preview"), ClayBench_TextConfig(20, clay_rgba(0.96f, 0.97f, 0.98f, 1)));
                CLAY(CLAY_ID("image"), { .layout = { .sizing = { .width = CLAY_SIZING_FIXED(320), .height = CLAY_SIZING_FIXED(180) } }, .image = { .imageData = &clay_dummy_image }, .border = { .color = clay_rgba(0.26f, 0.28f, 0.33f, 1), .width = CLAY_BORDER_OUTSIDE(1) } }) {}
                CLAY(CLAY_ID("stats"), { .layout = { .layoutDirection = CLAY_TOP_TO_BOTTOM, .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_FIT(0) }, .padding = CLAY_PADDING_ALL(8), .childGap = 4 }, .backgroundColor = clay_rgba(0.12f, 0.13f, 0.15f, 1), .border = { .color = clay_rgba(0.22f, 0.24f, 0.28f, 1), .width = CLAY_BORDER_OUTSIDE(1) } }) {
                    for (int i = 0; i < 8; ++i) {
                        char lhs[24], rhs[24];
                        snprintf(lhs, sizeof(lhs), "Metric %d", i);
                        snprintf(rhs, sizeof(rhs), "%d", 100 + i * 7);
                        CLAY_AUTO_ID({ .layout = { .layoutDirection = CLAY_LEFT_TO_RIGHT, .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_FIT(0) }, .childGap = 6 } }) {
                            CLAY_TEXT(clay_cstr(lhs), ClayBench_TextConfig(14, clay_rgba(0.92f, 0.93f, 0.95f, 1)));
                            CLAY_AUTO_ID({ .layout = { .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_FIT(0) } } }) {}
                            CLAY_TEXT(clay_cstr(rhs), ClayBench_TextConfig(14, clay_rgba(0.72f, 0.80f, 0.96f, 1)));
                        }
                    }
                }
            }

            CLAY(CLAY_ID("inspector"), { .layout = { .layoutDirection = CLAY_TOP_TO_BOTTOM, .sizing = { .width = CLAY_SIZING_FIXED(240), .height = CLAY_SIZING_GROW(0) }, .padding = CLAY_PADDING_ALL(8), .childGap = 4 }, .backgroundColor = clay_rgba(0.12f, 0.13f, 0.15f, 1), .border = { .color = clay_rgba(0.22f, 0.24f, 0.28f, 1), .width = CLAY_BORDER_OUTSIDE(1) } }) {
                CLAY_TEXT(CLAY_STRING("Inspector"), ClayBench_TextConfig(18, clay_rgba(0.96f, 0.97f, 0.98f, 1)));
                for (int i = 0; i < 12; ++i) {
                    char lhs[24], rhs[24];
                    snprintf(lhs, sizeof(lhs), "Field %d", i);
                    snprintf(rhs, sizeof(rhs), "Value %d", i * 3);
                    CLAY_AUTO_ID({ .layout = { .layoutDirection = CLAY_LEFT_TO_RIGHT, .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_FIT(0) }, .childGap = 6 } }) {
                        CLAY_TEXT(clay_cstr(lhs), ClayBench_TextConfig(14, clay_rgba(0.92f, 0.93f, 0.95f, 1)));
                        CLAY_AUTO_ID({ .layout = { .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_FIT(0) } } }) {}
                        CLAY_TEXT(clay_cstr(rhs), ClayBench_TextConfig(14, clay_rgba(0.72f, 0.80f, 0.96f, 1)));
                    }
                }
            }
        }
    }

    Clay_RenderCommandArray cmds = Clay_EndLayout();
    ClayBench_FillStats(cmds, Clay_GetCurrentContext()->layoutElements.length, out_stats);
}
