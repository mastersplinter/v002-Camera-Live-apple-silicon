#include "CameraLiveNative.h"
#include <gphoto2/gphoto2.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct CLDeviceList { CameraList *list; };
struct CLCancellation { atomic_bool cancelled; };
struct CLSession { Camera *camera; GPContext *context; int initialized; };

void cl_configure_drivers(const char *camlibs, const char *iolibs) {
    if (camlibs) setenv("CAMLIBS", camlibs, 1);
    if (iolibs) setenv("IOLIBS", iolibs, 1);
}
const char *cl_error_string(int code) { return gp_result_as_string(code); }
int cl_error_is_transient(int code) { return code == GP_ERROR_CAMERA_BUSY || code == GP_ERROR_TIMEOUT; }
CLCancellation *cl_cancellation_new(void) {
    CLCancellation *token = calloc(1, sizeof(*token));
    if (token) atomic_init(&token->cancelled, false);
    return token;
}
void cl_cancellation_cancel(CLCancellation *token) { if (token) atomic_store(&token->cancelled, true); }
void cl_cancellation_free(CLCancellation *token) { free(token); }
static GPContextFeedback cancelled(GPContext *context, void *data) {
    return atomic_load(&((CLCancellation *)data)->cancelled) ? GP_CONTEXT_FEEDBACK_CANCEL : GP_CONTEXT_FEEDBACK_OK;
}
int cl_list_devices(CLDeviceList **result) {
    *result = NULL;
    CLDeviceList *list = calloc(1, sizeof(*list));
    GPContext *context = gp_context_new();
    if (!list || !context) { free(list); if (context) gp_context_unref(context); return GP_ERROR_NO_MEMORY; }
    int code = gp_list_new(&list->list);
    if (code >= GP_OK) code = gp_camera_autodetect(list->list, context);
    gp_context_unref(context);
    if (code < GP_OK) { cl_list_free(list); return code; }
    *result = list;
    return GP_OK;
}
int cl_list_count(const CLDeviceList *list) { return list ? gp_list_count(list->list) : 0; }
const char *cl_list_model(const CLDeviceList *list, int index) {
    const char *value = NULL;
    if (list) gp_list_get_name(list->list, index, &value);
    return value;
}
const char *cl_list_port(const CLDeviceList *list, int index) {
    const char *value = NULL;
    if (list) gp_list_get_value(list->list, index, &value);
    return value;
}
void cl_list_free(CLDeviceList *list) { if (list) { if (list->list) gp_list_free(list->list); free(list); } }

int cl_session_open(const char *model, const char *port, CLCancellation *token, CLSession **result) {
    *result = NULL;
    CLSession *session = calloc(1, sizeof(*session));
    if (!session) return GP_ERROR_NO_MEMORY;
    CameraAbilitiesList *abilities = NULL;
    GPPortInfoList *ports = NULL;
    CameraAbilities ability;
    GPPortInfo portInfo;
    int code = GP_ERROR_NO_MEMORY;
    session->context = gp_context_new();
    if (!session->context) goto failure;
    if (token) gp_context_set_cancel_func(session->context, cancelled, token);
    #define CHECK(call) do { code = (call); if (code < GP_OK) goto failure; } while (0)
    CHECK(gp_camera_new(&session->camera));
    CHECK(gp_abilities_list_new(&abilities));
    CHECK(gp_abilities_list_load(abilities, session->context));
    CHECK(gp_abilities_list_lookup_model(abilities, model));
    CHECK(gp_abilities_list_get_abilities(abilities, code, &ability));
    if (!(ability.operations & GP_OPERATION_CAPTURE_PREVIEW)) { code = GP_ERROR_NOT_SUPPORTED; goto failure; }
    CHECK(gp_camera_set_abilities(session->camera, ability));
    CHECK(gp_port_info_list_new(&ports));
    CHECK(gp_port_info_list_load(ports));
    CHECK(gp_port_info_list_lookup_path(ports, port));
    CHECK(gp_port_info_list_get_info(ports, code, &portInfo));
    CHECK(gp_camera_set_port_info(session->camera, portInfo));
    CHECK(gp_camera_init(session->camera, session->context));
    session->initialized = 1;
    gp_abilities_list_free(abilities);
    gp_port_info_list_free(ports);
    *result = session;
    return GP_OK;
failure:
    if (abilities) gp_abilities_list_free(abilities);
    if (ports) gp_port_info_list_free(ports);
    cl_session_close(session);
    return code;
    #undef CHECK
}
int cl_session_preview(CLSession *session, void **bytes, size_t *length) {
    *bytes = NULL;
    *length = 0;
    CameraFile *file = NULL;
    int code = gp_file_new(&file);
    if (code < GP_OK) return code;
    code = gp_camera_capture_preview(session->camera, file, session->context);
    const char *data = NULL;
    unsigned long size = 0;
    if (code >= GP_OK) code = gp_file_get_data_and_size(file, &data, &size);
    if (code >= GP_OK) {
        if (!data || size == 0 || size > 32 * 1024 * 1024) code = GP_ERROR_CORRUPTED_DATA;
        else {
            *bytes = malloc(size);
            if (!*bytes) code = GP_ERROR_NO_MEMORY;
            else { memcpy(*bytes, data, size); *length = size; }
        }
    }
    gp_file_free(file);
    return code;
}
static int viewfinder(CLSession *session, int enabled) {
    CameraWidget *widget = NULL;
    int code = gp_camera_get_single_config(session->camera, "viewfinder", &widget, session->context);
    if (code >= GP_OK) {
        CameraWidgetType type;
        code = gp_widget_get_type(widget, &type);
        if (code >= GP_OK && type != GP_WIDGET_TOGGLE) code = GP_ERROR_NOT_SUPPORTED;
        if (code >= GP_OK) code = gp_widget_set_value(widget, &enabled);
        if (code >= GP_OK) code = gp_camera_set_single_config(session->camera, "viewfinder", widget, session->context);
    }
    if (widget) gp_widget_free(widget);
    return code;
}
int cl_session_keep_alive(CLSession *session) { return viewfinder(session, 1); }
void cl_bytes_free(void *bytes) { free(bytes); }
void cl_session_close(CLSession *session) {
    if (!session) return;
    if (session->camera) {
        if (session->initialized) {
            // Cancellation must not prevent restoring the camera and closing PTP.
            gp_context_set_cancel_func(session->context, NULL, NULL);
            viewfinder(session, 0);
            gp_camera_exit(session->camera, session->context);
        }
        gp_camera_unref(session->camera);
    }
    if (session->context) gp_context_unref(session->context);
    free(session);
}
