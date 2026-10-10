// SPDX-License-Identifier: Apache-2.0
// Part of Fingertip-dit: https://github.com/galetaire/Fingertip-dit
// hnsd wrapper for Fingertip.
// Fingertip launches "hnsd.exe" with fixed arguments. This wrapper starts the
// real binary (hnsd-core.exe, same folder) with --checkpoint and --prefix added,
// so the chain syncs from a recent checkpoint and headers persist across restarts.
// The child is placed in a kill-on-close job so it dies when the wrapper dies.
#include <windows.h>
#include <wchar.h>

static const wchar_t *skip_argv0(const wchar_t *cmd) {
  if (*cmd == L'"') {
    cmd++;
    while (*cmd && *cmd != L'"') cmd++;
    if (*cmd) cmd++;
  } else {
    while (*cmd && *cmd != L' ' && *cmd != L'\t') cmd++;
  }
  while (*cmd == L' ' || *cmd == L'\t') cmd++;
  return cmd;
}

int wmain(void) {
  wchar_t dir[MAX_PATH];
  DWORD n = GetModuleFileNameW(NULL, dir, MAX_PATH);
  if (n == 0 || n >= MAX_PATH) return 1;
  wchar_t *slash = wcsrchr(dir, L'\\');
  if (slash) *slash = 0;

  wchar_t exe[MAX_PATH + 32], data[MAX_PATH + 32];
  swprintf(exe, MAX_PATH + 32, L"%ls\\hnsd-core.exe", dir);
  swprintf(data, MAX_PATH + 32, L"%ls\\hnsd-data", dir);
  CreateDirectoryW(data, NULL);

  const wchar_t *rest = skip_argv0(GetCommandLineW());
  size_t len = wcslen(exe) + wcslen(data) + wcslen(rest) + 64;
  wchar_t *cmd = HeapAlloc(GetProcessHeap(), 0, len * sizeof(wchar_t));
  if (!cmd) return 1;
  swprintf(cmd, len, L"\"%ls\" --checkpoint --prefix \"%ls\" %ls", exe, data, rest);

  HANDLE job = CreateJobObjectW(NULL, NULL);
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION info = {0};
  info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  SetInformationJobObject(job, JobObjectExtendedLimitInformation, &info, sizeof(info));

  STARTUPINFOW si = {0};
  si.cb = sizeof(si);
  si.dwFlags = STARTF_USESTDHANDLES;
  si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
  si.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
  si.hStdError = GetStdHandle(STD_ERROR_HANDLE);
  PROCESS_INFORMATION pi;

  if (!CreateProcessW(exe, cmd, NULL, NULL, TRUE, CREATE_SUSPENDED, NULL, dir, &si, &pi))
    return 1;
  AssignProcessToJobObject(job, pi.hProcess);
  ResumeThread(pi.hThread);
  CloseHandle(pi.hThread);

  WaitForSingleObject(pi.hProcess, INFINITE);
  DWORD code = 1;
  GetExitCodeProcess(pi.hProcess, &code);
  return (int)code;
}
