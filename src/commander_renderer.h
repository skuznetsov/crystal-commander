#ifndef COMMANDER_RENDERER_H
#define COMMANDER_RENDERER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum commander_row_flags {
  COMMANDER_ROW_FLAG_DIRECTORY = 1u << 0,
  COMMANDER_ROW_FLAG_EXECUTABLE = 1u << 1,
  COMMANDER_ROW_FLAG_PARENT = 1u << 2,
  COMMANDER_ROW_FLAG_MARKED = 1u << 3
};

enum commander_event_type {
  COMMANDER_EVENT_NONE = 0,
  COMMANDER_EVENT_KEY = 1,
  COMMANDER_EVENT_MOUSE_DOWN = 2,
  COMMANDER_EVENT_ROW_SELECTED = 3,
  COMMANDER_EVENT_ROW_ACTIVATED = 4,
  COMMANDER_EVENT_TAB = 5,
  COMMANDER_EVENT_WINDOW_CLOSE = 6,
  COMMANDER_EVENT_QUIT = 7
};

typedef struct commander_render_row {
  const char *name;
  const char *size;
  const char *modified;
  uint32_t flags;
} commander_render_row_t;

typedef struct commander_render_event {
  int32_t type;
  int32_t panel;
  int32_t key_code;
  uint32_t modifiers;
  int32_t row;
  int32_t button;
  uint32_t click_count;
  double x;
  double y;
} commander_render_event_t;

void *commander_renderer_create(int32_t panel_count, int32_t width, int32_t height);
void commander_renderer_destroy(void *handle);

int32_t commander_renderer_show(void *handle);
int32_t commander_renderer_pump(void *handle, int32_t wait_ms);
void commander_renderer_stop(void *handle);

int32_t commander_renderer_poll_event(void *handle, commander_render_event_t *out_event);

void commander_renderer_set_active_panel(void *handle, int32_t panel_index);
void commander_renderer_set_status_text(void *handle, const char *text);
void commander_renderer_set_panel_path(void *handle, int32_t panel_index, const char *path);
void commander_renderer_set_panel_rows(void *handle, int32_t panel_index, const commander_render_row_t *rows, int32_t row_count, int32_t cursor);
void commander_renderer_set_panel_cursor(void *handle, int32_t panel_index, int32_t selected_index);

void commander_renderer_get_mouse_position(void *handle, double *x, double *y);
void commander_renderer_set_mouse_visible(int32_t visible);

/* Backward-compatible blocking entrypoint. */
void commander_renderer_run(int panel_count);

#ifdef __cplusplus
}
#endif

#endif
