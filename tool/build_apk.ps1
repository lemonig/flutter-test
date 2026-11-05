# 一键构建三类 APK（Windows PowerShell）
#
# 用法：
#   pwsh tool/build_apk.ps1              # 构建 dev + prod
#   pwsh tool/build_apk.ps1 -Target all # demo + dev + prod
#   pwsh tool/build_apk.ps1 -Target dev
#
# 产物复制到 dist/ 并带环境后缀，避免再次出现「装了包却不知道连的是哪台机器」。

param(
    # dev / uat / prod / demo / all，也可用逗号组合：dev,prod
    [string[]]$Target = @('dev', 'prod')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# 本地工具链与国内镜像
if (-not $env:JAVA_HOME -and (Test-Path 'E:\JDK')) { $env:JAVA_HOME = 'E:\JDK' }
if (-not $env:ANDROID_HOME -and (Test-Path 'E:\tools\android-sdk')) {
    $env:ANDROID_HOME = 'E:\tools\android-sdk'
    $env:ANDROID_SDK_ROOT = 'E:\tools\android-sdk'
}
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:NO_PROXY = 'localhost,127.0.0.1,::1'

$flutter = 'E:\tools\flutter\bin\flutter.bat'
if (-not (Test-Path $flutter)) { $flutter = 'flutter' }

$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null

$recipes = @{
    demo = @{
        Args = @('--dart-define=FLAVOR=dev', '--dart-define=USE_MOCK=true')
        Name = 'green-ops-demo.apk'
        Desc = '本地演示数据，不发起网络请求'
    }
    dev = @{
        Args = @('--dart-define=FLAVOR=dev', '--dart-define=USE_MOCK=false')
        Name = 'green-ops-dev.apk'
        Desc = '局域网后端 http://192.168.188.66:1601/api/'
    }
    uat = @{
        Args = @('--dart-define=FLAVOR=staging', '--dart-define=USE_MOCK=false')
        Name = 'green-ops-uat.apk'
        Desc = 'UAT 后端 http://47.111.166.172:1600/api/'
    }
    prod = @{
        Args = @('--dart-define=FLAVOR=prod', '--dart-define=USE_MOCK=false')
        Name = 'green-ops-prod.apk'
        Desc = '正式服务器 https://app.greandata1.com/api/'
    }
}

# 参数可能是数组（dev,prod）或单串，统一切成小写、去空格的列表
$targets = @()
foreach ($raw in @($Target)) {
    foreach ($part in ($raw -split '[,;]')) {
        $t = $part.Trim().ToLower()
        if ($t) { $targets += $t }
    }
}
if ($targets -contains 'all') { $targets = @('demo', 'dev', 'prod') }

$built = @()
foreach ($t in $targets) {
    if (-not $recipes.ContainsKey($t)) {
        throw "Unknown target: $t (choose from demo/dev/uat/prod/all)"
    }
    $recipe = $recipes[$t]
    Write-Output "==> 构建 $t : $($recipe.Desc)"
    $flutterArgs = @('build', 'apk', '--debug') + $recipe.Args
    # flutter 会把提示信息写到 stderr（如 "Flutter assets will be downloaded..."），
    # 在 $ErrorActionPreference='Stop' 下会被升级成终止错误，必须临时放开。
    $prevPref = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $flutter @flutterArgs 2>&1 | ForEach-Object { Write-Output $_ }
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $prevPref
    if ($exitCode -ne 0) { throw "Build $t failed (exit $exitCode)" }

    $src = Join-Path $root 'build\app\outputs\flutter-apk\app-debug.apk'
    $dst = Join-Path $dist $recipe.Name
    Copy-Item $src $dst -Force
    $sizeMb = [math]::Round((Get-Item $dst).Length / 1MB, 1)
    $built += [pscustomobject]@{ 包 = $recipe.Name; 环境 = $t; 大小 = "$sizeMb MB"; 指向 = $recipe.Desc }
}

$built | Format-Table -AutoSize
Write-Output "产物目录：$dist"
