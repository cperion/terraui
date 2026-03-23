#ifndef TERRAUI_CLAY_BENCH_H
#define TERRAUI_CLAY_BENCH_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ClayBenchStats {
    int element_count;
    int command_count;
    int rect_count;
    int border_count;
    int text_count;
    int image_count;
    int scissor_count;
    int custom_count;
    int had_error;
} ClayBenchStats;

void ClayBench_BuildFlatList(int item_count, int viewport_w, int viewport_h, ClayBenchStats *out_stats);
void ClayBench_BuildTextHeavy(int item_count, int viewport_w, int viewport_h, ClayBenchStats *out_stats);
void ClayBench_BuildNestedPanels(int group_count, int viewport_w, int viewport_h, ClayBenchStats *out_stats);
void ClayBench_BuildInspectorMini(int item_count, int viewport_w, int viewport_h, ClayBenchStats *out_stats);

#ifdef __cplusplus
}
#endif

#endif
