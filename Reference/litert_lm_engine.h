// Reference copy of the C API header from CLiteRTLM.xcframework.
// This file is NOT used during build — it's here for documentation.
// The actual header is embedded inside the xcframework binary target.
//
// C API surface for LiteRT-LM engine, built from:
// https://github.com/google-ai-edge/LiteRT-LM

#ifndef LITERT_LM_ENGINE_H
#define LITERT_LM_ENGINE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Opaque Types
// ---------------------------------------------------------------------------

typedef struct LiteRtLmEngine LiteRtLmEngine;
typedef struct LiteRtLmEngineSettings LiteRtLmEngineSettings;
typedef struct LiteRtLmSession LiteRtLmSession;
typedef struct LiteRtLmSessionConfig LiteRtLmSessionConfig;
typedef struct LiteRtLmSamplerParams LiteRtLmSamplerParams;
typedef struct LiteRtLmResponses LiteRtLmResponses;
typedef struct LiteRtLmConversation LiteRtLmConversation;
typedef struct LiteRtLmConversationConfig LiteRtLmConversationConfig;
typedef struct LiteRtLmJsonResponse LiteRtLmJsonResponse;
typedef struct LiteRtLmBenchmarkInfo LiteRtLmBenchmarkInfo;
typedef struct InputData InputData;

// Logging
void litert_lm_set_min_log_level(int level);

// Engine Settings
LiteRtLmEngineSettings* litert_lm_engine_settings_create(const char* model_path, const char* backend, const char* backend2, const char* backend3);
void litert_lm_engine_settings_set_max_num_tokens(LiteRtLmEngineSettings* settings, int max_tokens);
void litert_lm_engine_settings_set_cache_dir(LiteRtLmEngineSettings* settings, const char* cache_dir);
void litert_lm_engine_settings_enable_benchmark(LiteRtLmEngineSettings* settings);
void litert_lm_engine_settings_delete(LiteRtLmEngineSettings* settings);

// Engine
LiteRtLmEngine* litert_lm_engine_create(LiteRtLmEngineSettings* settings);
void litert_lm_engine_delete(LiteRtLmEngine* engine);

// Sampler
LiteRtLmSamplerParams* litert_lm_sampler_params_create(void);
void litert_lm_sampler_params_set_temperature(LiteRtLmSamplerParams* params, float temperature);
void litert_lm_sampler_params_set_top_k(LiteRtLmSamplerParams* params, int32_t top_k);
void litert_lm_sampler_params_set_top_p(LiteRtLmSamplerParams* params, float top_p);
void litert_lm_sampler_params_delete(LiteRtLmSamplerParams* params);

// Session Config
LiteRtLmSessionConfig* litert_lm_session_config_create(void);
void litert_lm_session_config_set_max_output_tokens(LiteRtLmSessionConfig* config, int32_t max_tokens);
void litert_lm_session_config_set_sampler_params(LiteRtLmSessionConfig* config, LiteRtLmSamplerParams* params);
void litert_lm_session_config_delete(LiteRtLmSessionConfig* config);

// Session
LiteRtLmSession* litert_lm_engine_create_session(LiteRtLmEngine* engine, LiteRtLmSessionConfig* config);
void litert_lm_session_delete(LiteRtLmSession* session);

// Generation (blocking)
LiteRtLmResponses* litert_lm_session_generate_content(LiteRtLmSession* session, InputData* inputs, int num_inputs);
int litert_lm_responses_get_num_candidates(LiteRtLmResponses* responses);
const char* litert_lm_responses_get_response_text_at(LiteRtLmResponses* responses, int index);
void litert_lm_responses_delete(LiteRtLmResponses* responses);

// Generation (streaming)
typedef void (*LiteRtLmStreamCallback)(void* callback_data, const char* token, bool is_done, const char* error);
int32_t litert_lm_session_generate_content_stream(LiteRtLmSession* session, InputData* inputs, int num_inputs, LiteRtLmStreamCallback callback, void* callback_data);

// Input Data
InputData* litert_lm_input_data_create_text(const char* text);
InputData* litert_lm_input_data_create_image(const void* data, int length);
InputData* litert_lm_input_data_create_audio(const void* data, int length, const char* format);
void litert_lm_input_data_delete(InputData* input);

// Conversation
LiteRtLmConversationConfig* litert_lm_conversation_config_create(LiteRtLmEngine* engine, LiteRtLmSessionConfig* session_config, void* p1, void* p2, void* p3, bool p4);
void litert_lm_conversation_config_delete(LiteRtLmConversationConfig* config);
LiteRtLmConversation* litert_lm_conversation_create(LiteRtLmEngine* engine, LiteRtLmConversationConfig* config);
void litert_lm_conversation_delete(LiteRtLmConversation* conversation);
LiteRtLmJsonResponse* litert_lm_conversation_send_message(LiteRtLmConversation* conversation, const char* message, void* extra);
const char* litert_lm_json_response_get_string(LiteRtLmJsonResponse* response);
void litert_lm_json_response_delete(LiteRtLmJsonResponse* response);

// Benchmark
LiteRtLmBenchmarkInfo* litert_lm_session_get_benchmark_info(LiteRtLmSession* session);
void litert_lm_benchmark_info_delete(LiteRtLmBenchmarkInfo* info);
double litert_lm_benchmark_info_get_total_init_time_in_second(LiteRtLmBenchmarkInfo* info);
double litert_lm_benchmark_info_get_time_to_first_token(LiteRtLmBenchmarkInfo* info);
int litert_lm_benchmark_info_get_num_decode_turns(LiteRtLmBenchmarkInfo* info);
int litert_lm_benchmark_info_get_num_prefill_turns(LiteRtLmBenchmarkInfo* info);
double litert_lm_benchmark_info_get_prefill_tokens_per_sec_at(LiteRtLmBenchmarkInfo* info, int32_t index);
int litert_lm_benchmark_info_get_prefill_token_count_at(LiteRtLmBenchmarkInfo* info, int32_t index);
double litert_lm_benchmark_info_get_decode_tokens_per_sec_at(LiteRtLmBenchmarkInfo* info, int32_t index);
int litert_lm_benchmark_info_get_decode_token_count_at(LiteRtLmBenchmarkInfo* info, int32_t index);

#ifdef __cplusplus
}
#endif

#endif // LITERT_LM_ENGINE_H
