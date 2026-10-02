#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include "ecqt.h"
// One context per Dart analysis worker; no transform-time allocations.
typedef struct { CQTContext *ctx; CQTResult *result; float *input; float output[84]; } ShirrCqt;
__attribute__((visibility("default"))) void *shirr_cqt_create(void) {
 ShirrCqt *s=calloc(1,sizeof(*s)); if(!s)return NULL;
 s->ctx=cqtcontext_init(65.406391f,22050,12,0.001f);
 s->result=cqtresult_init(65.406391f,22050,12);
 if(!s->ctx||!s->result){cqtcontext_deinit(s->ctx);cqtresult_deinit(s->result);free(s);return NULL;}
 s->input=calloc(s->ctx->inlen,sizeof(float));
 if(!s->input){cqtcontext_deinit(s->ctx);cqtresult_deinit(s->result);free(s);return NULL;}
 return s;
}
__attribute__((visibility("default"))) float *shirr_cqt_input(ShirrCqt *s){return s->input;}
__attribute__((visibility("default"))) int shirr_cqt_length(ShirrCqt *s){return s->ctx->inlen;}
__attribute__((visibility("default"))) float *shirr_cqt_run(ShirrCqt *s){
 if(cqtcontext_transform(s->ctx,s->input,s->ctx->inlen,s->result))return NULL;
 for(int i=0;i<84;i++)s->output[i]=i<s->result->bins?ecqt_abs(s->result->prv->entries[i]):0;
 return s->output;
}
__attribute__((visibility("default"))) void shirr_cqt_destroy(ShirrCqt *s){
 if(!s)return; cqtcontext_deinit(s->ctx);cqtresult_deinit(s->result);free(s->input);free(s);
}
