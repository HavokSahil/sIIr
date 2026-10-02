#include <jni.h>

// The version symbol is exported by libessentia. These placeholder methods
// need no algorithm headers (or their optional Eigen tensor dependencies).
namespace essentia {
extern const char* version;
}

extern "C" {

JNIEXPORT jstring JNICALL
Java_com_example_shirr_MainActivity_getEssentiaVersion(JNIEnv* env, jclass) {
    return env->NewStringUTF(essentia::version);
}

// Detection remains unimplemented. The Flutter observatory uses its Dart DSP
// engine. Do not acquire/pin Java audio arrays just to return an empty result.
JNIEXPORT jfloatArray JNICALL
Java_com_example_shirr_MainActivity_detectBeats(JNIEnv* env, jclass, jfloatArray, jint) {
    return env->NewFloatArray(0);
}

JNIEXPORT jfloatArray JNICALL
Java_com_example_shirr_MainActivity_detectOnsets(JNIEnv* env, jclass, jfloatArray, jint) {
    return env->NewFloatArray(0);
}

JNIEXPORT jfloatArray JNICALL
Java_com_example_shirr_MainActivity_detectPitch(JNIEnv* env, jclass, jfloatArray, jint) {
    return env->NewFloatArray(0);
}

}
