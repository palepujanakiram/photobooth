#include <android/log.h>
#include <fcntl.h>
#include <jni.h>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>

#include <cerrno>
#include <cstring>
#include <string>
#include <vector>

extern char **environ;

#define LOG_TAG "CanonSidecarSpawn"
#define ALOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define ALOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

namespace {

struct SpawnSpec {
    std::string interpreter;
    std::string cwd;
    std::string preload;
    std::string usbPath;
    std::vector<std::string> argStore;
    jint usbFd = -1;
};

std::string jstringToUtf8(JNIEnv *env, jstring value) {
    if (value == nullptr) {
        return {};
    }
    const char *chars = env->GetStringUTFChars(value, nullptr);
    std::string out = chars != nullptr ? chars : "";
    if (chars != nullptr) {
        env->ReleaseStringUTFChars(value, chars);
    }
    return out;
}

void clearCloexec(int fd) {
    if (fd < 0) {
        return;
    }
    int flags = fcntl(fd, F_GETFD);
    if (flags >= 0) {
        fcntl(fd, F_SETFD, flags & ~FD_CLOEXEC);
    }
}

bool startsWith(const char *value, const char *prefix, size_t prefixLen) {
    return std::strncmp(value, prefix, prefixLen) == 0;
}

bool skipInheritedEnv(const char *entry) {
    return startsWith(entry, "LD_PRELOAD=", 11) ||
           startsWith(entry, "CANON_USB_FD=", 13) ||
           startsWith(entry, "CANON_USB_PATH=", 15) ||
           startsWith(entry, "LIBUSB_DEBUG=", 13);
}

std::vector<std::string> readJniArgs(JNIEnv *env, jstring interpreter, jobjectArray jArgs) {
    std::vector<std::string> argStore;
    argStore.push_back(jstringToUtf8(env, interpreter));
    if (jArgs == nullptr) {
        return argStore;
    }
    const jsize argc = env->GetArrayLength(jArgs);
    for (jsize i = 0; i < argc; ++i) {
        auto arg = reinterpret_cast<jstring>(env->GetObjectArrayElement(jArgs, i));
        argStore.push_back(jstringToUtf8(env, arg));
        if (arg != nullptr) {
            env->DeleteLocalRef(arg);
        }
    }
    return argStore;
}

std::vector<std::string> buildChildEnv(const SpawnSpec &spec) {
    std::vector<std::string> envStore;
    for (char **e = environ; e != nullptr && *e != nullptr; ++e) {
        if (!skipInheritedEnv(*e)) {
            envStore.emplace_back(*e);
        }
    }
    if (!spec.preload.empty()) {
        envStore.emplace_back("LD_PRELOAD=" + spec.preload);
    }
    if (spec.usbFd >= 0 && !spec.usbPath.empty()) {
        envStore.emplace_back("CANON_USB_FD=" + std::to_string(spec.usbFd));
        envStore.emplace_back("CANON_USB_PATH=" + spec.usbPath);
        envStore.emplace_back("LIBUSB_DEBUG=3");
    }
    return envStore;
}

std::vector<char *> pointersTo(std::vector<std::string> &store) {
    std::vector<char *> ptrs;
    ptrs.reserve(store.size() + 1);
    for (auto &entry : store) {
        ptrs.push_back(entry.data());
    }
    ptrs.push_back(nullptr);
    return ptrs;
}

void execChild(const SpawnSpec &spec, char **argv, char **envp, int writePipe) {
    dup2(writePipe, STDOUT_FILENO);
    dup2(writePipe, STDERR_FILENO);
    if (writePipe > STDERR_FILENO) {
        close(writePipe);
    }
    clearCloexec(spec.usbFd);
    if (!spec.cwd.empty() && chdir(spec.cwd.c_str()) != 0) {
        _exit(127);
    }
    execve(spec.interpreter.c_str(), argv, envp);
    _exit(127);
}

pid_t forkSidecar(const SpawnSpec &spec, char **argv, char **envp, int pipefd[2]) {
    const pid_t pid = fork();
    if (pid < 0) {
        ALOGE("fork failed: %s", std::strerror(errno));
        close(pipefd[0]);
        close(pipefd[1]);
        return -1;
    }
    if (pid == 0) {
        close(pipefd[0]);
        execChild(spec, argv, envp, pipefd[1]);
    }
    close(pipefd[1]);
    return pid;
}

jintArray packSpawnResult(JNIEnv *env, pid_t pid, int stdoutFd) {
    jintArray result = env->NewIntArray(2);
    if (result == nullptr) {
        close(stdoutFd);
        kill(pid, SIGKILL);
        waitpid(pid, nullptr, 0);
        return nullptr;
    }
    const jint values[2] = {static_cast<jint>(pid), static_cast<jint>(stdoutFd)};
    env->SetIntArrayRegion(result, 0, 2, values);
    return result;
}

struct JniSpawnInput {
    jstring interpreter;
    jobjectArray args;
    jstring cwd;
    jstring preload;
    jint usbFd;
    jstring usbPath;
};

SpawnSpec readSpawnSpec(JNIEnv *env, const JniSpawnInput &input) {
    SpawnSpec spec;
    spec.interpreter = jstringToUtf8(env, input.interpreter);
    spec.cwd = jstringToUtf8(env, input.cwd);
    spec.preload = jstringToUtf8(env, input.preload);
    spec.usbPath = jstringToUtf8(env, input.usbPath);
    spec.argStore = readJniArgs(env, input.interpreter, input.args);
    spec.usbFd = input.usbFd;
    return spec;
}

}  // namespace

extern "C" JNIEXPORT jintArray JNICALL
Java_com_srisarani_fotozenai_canon_CanonSidecarSpawner_nativeSpawn(
    JNIEnv *env,
    jclass,
    jstring jInterpreter,
    jobjectArray jArgs,
    jstring jCwd,
    jstring jPreload,
    jint usbFd,
    jstring jUsbPath) {
    SpawnSpec spec = readSpawnSpec(
        env,
        JniSpawnInput{
            jInterpreter,
            jArgs,
            jCwd,
            jPreload,
            usbFd,
            jUsbPath,
        });
    auto argv = pointersTo(spec.argStore);
    auto envStore = buildChildEnv(spec);
    auto envp = pointersTo(envStore);

    int pipefd[2];
    if (pipe(pipefd) != 0) {
        ALOGE("pipe failed: %s", std::strerror(errno));
        return nullptr;
    }

    clearCloexec(spec.usbFd);
    const pid_t pid = forkSidecar(spec, argv.data(), envp.data(), pipefd);
    if (pid < 0) {
        return nullptr;
    }

    ALOGI(
        "spawned pid=%d usbFd=%d path=%s",
        static_cast<int>(pid),
        spec.usbFd,
        spec.usbPath.empty() ? "(none)" : spec.usbPath.c_str());
    return packSpawnResult(env, pid, pipefd[0]);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_srisarani_fotozenai_canon_CanonSidecarSpawner_nativeWaitPid(
    JNIEnv *,
    jclass,
    jint pid) {
    int status = 0;
    pid_t waited;
    do {
        waited = waitpid(static_cast<pid_t>(pid), &status, 0);
    } while (waited < 0 && errno == EINTR);
    if (waited < 0) {
        return -1;
    }
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    if (WIFSIGNALED(status)) {
        return 128 + WTERMSIG(status);
    }
    return 0;
}

extern "C" JNIEXPORT void JNICALL
Java_com_srisarani_fotozenai_canon_CanonSidecarSpawner_nativeKill(
    JNIEnv *,
    jclass,
    jint pid) {
    if (pid > 0) {
        kill(static_cast<pid_t>(pid), SIGKILL);
    }
}
