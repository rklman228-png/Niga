#ifndef NIGA_SPRINGBOARD_SERVICE_H
#define NIGA_SPRINGBOARD_SERVICE_H

#import <Foundation/Foundation.h>
#include <stdbool.h>

typedef void (^NigaSpringBoardCompletion)(bool completed);

bool niga_sbs_windowing_service_available(void);
void niga_sbs_request_windowing_mode(int mode, NigaSpringBoardCompletion completion);
void niga_sbs_request_reset_layout(NigaSpringBoardCompletion completion);
char *niga_sbs_copy_diagnostics(void);
char *niga_sbs_copy_gate_diagnostics(void);
void niga_sbs_free_string(char *value);

#endif
