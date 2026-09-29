# 看运（destiny）Android 构建脚本（由 build.cmd 调用）
# 职责：设置全部工具链环境变量 -> 依赖安装交给 gradle wrapper 自理（本工程为纯 Android，
# 无鸿蒙模块，故无 ohpm install 步骤）-> 执行 gradle 任务 -> 完整输出落 build-last.log，
# stdout 仅回显最后约 100 行，末行 BUILD_EXIT=<退出码>，进程以该码退出。
$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Log  = Join-Path $Root "build-last.log"

# ---- 工具链（本机事实）----
$env:JAVA_HOME       = "C:\Program Files\Eclipse Adoptium\jdk-21.0.10.7-hotspot"
$env:ANDROID_HOME    = "D:\Android\Sdk"
$env:DEVECO_SDK_HOME = "D:\Android\Sdk"
# 保证重定向日志为 UTF-8（gradle 客户端 JVM 同步生效），读取日志时按 UTF-8 解码
$env:GRADLE_OPTS     = "-Dfile.encoding=UTF-8"
$env:PATH = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"

# ---- 任务参数 ----
$Task = "assembleDebug"
if ($args.Count -ge 1 -and $args[0]) { $Task = [string]$args[0] }

"==== destiny-android build.ps1 task=$Task ===="
"JAVA_HOME=$env:JAVA_HOME"
"ANDROID_HOME=$env:ANDROID_HOME"

# 清空旧日志
if (Test-Path $Log) { Remove-Item $Log -Force | Out-Null }
Set-Content -Path $Log -Value "==== build start $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') task=$Task ====" -Encoding UTF8

Push-Location $Root
$sw = [System.Diagnostics.Stopwatch]::StartNew()
cmd /c "gradlew.bat $Task --stacktrace --warning-mode=summary >> `"$Log`" 2>&1"
$code = $LASTEXITCODE
$sw.Stop()
Pop-Location

# ---- stdout 只回显最后 100 行 ----
"---- tail $Log ----"
if (Test-Path $Log) {
    Get-Content $Log -Tail 100 -Encoding UTF8
} else {
    "(build-last.log 不存在)"
}
"==== build.ps1 done in $([int]$sw.Elapsed.TotalSeconds)s ===="
"BUILD_EXIT=$code"
exit $code
