#include "cpp_helper.h"

void call_source_process(android_app *state, android_poll_source *s) {
  // Delegating member function calls in C++
  s->process(state, s);
}

const float *get_acceleration(const ASensorEvent *event) {
  // anonymous union trouble ?
  return &event->acceleration.x;
}
