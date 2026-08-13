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
    const std::string interpreter = jstringToUtf8(env, jInterpreter);
    const std::string cwd = jstringToUtf8(env, jCwd);
    const std::string preload = jstringToUtf8(env, jPreload);
    const std::string usbPath = jstringToUtf8(env, jUsbPath);

    std::vector<std::string> argStore;
    argStore.push_back(interpreter);
    if (jArgs != nullptr) {
        const jsize argc = env->GetArrayLength(jArgs);
        for (jsize i = 0; i < argc; ++i) {
            auto arg = reinterpret_cast<jstring>(
                env->GetObjectArrayElement(jArgs, i));
            argStore.push_back(jstringToUtf8(env, arg));
            if (arg != nullptr) {
                env->DeleteLocalRef(arg);
            }
        }
    }

    std::vector<char *> argv;
    argv.reserve(argStore.size() + 1);
    for (auto &arg : argStore) {
        argv.push_back(arg.data());
    }
    argv.push_back(nullptr);

    std::vector<std::string> envStore;
    for (char **e = environ; e != nullptr && *e != nullptr; ++e) {
        if (std::strncmp(*e, "LD_PRELOAD=", 11) == 0) {
            continue;
        }
        if (std::strncmp(*e, "CANON_USB_FD=", 13) == 0) {
            continue;
        }
        if (std::strncmp(*e, "CANON_USB_PATH=", 15) == 0) {
            continue;
        }
        envStore.emplace_back(*e);
    }
    if (!preload.empty()) {
        envStore.emplace_back("LD_PRELOAD=" + preload);
    }
    if (usbFd >= 0 && !usbPath.empty()) {
        envStore.emplace_back("CANON_USB_FD=" + std::to_string(usbFd));
        envStore.emplace_back("CANON_USB_PATH=" + usbPath);
    }

    std::vector<char *> envp;
    envp.reserve(envStore.size() + 1);
    for (auto &entry : envStore) {
        envp.push_back(entry.data());
    }
    envp.push_back(nullptr);

    int pipefd[2];
    if (pipe(pipefd) != 0) {
        ALOGE("pipe failed: %s", std::strerror(errno));
        return nullptr;
    }

    clearCloexec(usbFd);

    const pid_t pid = fork();
    if (pid < 0) {
        ALOGE("fork failed: %s", std::strerror(errno));
        close(pipefd[0]);
        close(pipefd[1]);
        return nullptr;
    }

    if (pid == 0) {
        close(pipefd[0]);
        dup2(pipefd[1], STDOUT_FILENO);
        dup2(pipefd[1], STDERR_FILENO);
        if (pipefd[1] > STDERR_FILENO) {
            close(pipefd[1]);
        }
        clearCloexec(usbFd);
        if (!cwd.empty() && chdir(cwd.c_str()) != 0) {
            _exit(127);
        }
        execve(interpreter.c_str(), argv.data(), envp.data());
        _exit(127);
    }

    close(pipefd[1]);
    ALOGI(
        "spawned pid=%d usbFd=%d path=%s",
        static_cast<int>(pid),
        usbFd,
        usbPath.empty() ? "(none)" : usbPath.c_str());

    jintArray result = env->NewIntArray(2);
    if (result == nullptr) {
        close(pipefd[0]);
        kill(pid, SIGKILL);
        waitpid(pid, nullptr, 0);
        return nullptr;
    }
    const jint values[2] = {static_cast<jint>(pid), static_cast<jint>(pipefd[0])};
    env->SetIntArrayRegion(result, 0, 2, values);
    return result;
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
