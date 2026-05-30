# Parallel-JobManager

A PowerShell utility that manages parallel job execution using **Runspaces**, 
with built-in progress tracking, real-time output streaming, and automatic 
stream flushing.

---

## ✨ Features

- ✅ Run multiple jobs concurrently with a configurable slot limit
- ✅ Real-time output from jobs via `ConcurrentQueue`
- ✅ Progress bar showing queued, running, and completed jobs
- ✅ Automatic Warning and Error stream flushing per job
- ✅ Non-blocking job drain while waiting for free slots
- ✅ Colored output support from inside jobs

---

## 📋 Functions

| Function | Description |
|---|---|
| `New-RunspaceManager` | Creates and opens a runspace pool manager |
| `Add-RunspaceJob` | Adds a job to the manager and starts it |
| `Wait-RunspaceManager` | Waits for all jobs to finish, then cleans up |
| `Clear-CompletedJobs` | Removes finished jobs and flushes their output |
| `Drain-RunningQueues` | Drains output queues of currently running jobs |
| `Drain-JobQueue` | Drains the output queue of a single job |
| `Flush-JobStreams` | Flushes Warning and Error streams of a finished job |

---

## 🚀 Quick Start

### 1. Basic usage

```powershell
$mgr = New-RunspaceManager -MaxConcurrent 10

$job = {
    param($name, $queue)
    $queue.Enqueue("Hello from $name!")
    Start-Sleep -Seconds 2
    $queue.Enqueue("$name finished.")
}

foreach ($i in 1..20) {
    $mgr | Add-RunspaceJob -ScriptBlock $job -Arguments @("Job-$i") -Label "Job-$i"
}

$mgr | Wait-RunspaceManager
```

---

### 2. With real-time output (-FlushOnRunning)

Print messages from jobs **as they run**, without waiting for them to finish.

```powershell
$mgr = New-RunspaceManager -MaxConcurrent 5 -FlushOnRunning

$job = {
    param($id, $queue)
    $queue.Enqueue("[$id] Starting...")
    Start-Sleep -Seconds 1
    $queue.Enqueue("[$id] Done!")
}

foreach ($i in 1..10) {
    $mgr | Add-RunspaceJob -ScriptBlock $job -Arguments @($i) -Label "Task-$i"
}

$mgr | Wait-RunspaceManager
```

---

### 3. With colored output

Send colored messages from inside a job using a PSCustomObject.

```powershell
$mgr = New-RunspaceManager -MaxConcurrent 5 -FlushOnRunning

$job = {
    param($id, $queue)
    $queue.Enqueue([PSCustomObject]@{ Message = "[$id] This is green!"; Color = "Green" })
    $queue.Enqueue([PSCustomObject]@{ Message = "[$id] This is red!";   Color = "Red"   })
}

foreach ($i in 1..5) {
    $mgr | Add-RunspaceJob -ScriptBlock $job -Arguments @($i) -Label "ColorJob-$i"
}

$mgr | Wait-RunspaceManager
```

---

### 4. Flush output only on completion (-FlushOnCompleted)

Print all messages from a job only **after it finishes**.

```powershell
$mgr = New-RunspaceManager -MaxConcurrent 5 -FlushOnCompleted

$job = {
    param($id, $queue)
    for ($i = 1; $i -le 5; $i++) {
        $queue.Enqueue("[$id] Step $i of 5")
        Start-Sleep -Milliseconds 500
    }
}

foreach ($i in 1..10) {
    $mgr | Add-RunspaceJob -ScriptBlock $job -Arguments @($i) -Label "Task-$i"
}

$mgr | Wait-RunspaceManager
```

---

## ⚙️ Parameters

### New-RunspaceManager

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-MaxConcurrent` | `int` | `25` | Maximum number of jobs running at the same time |
| `-FlushOnRunning` | `switch` | `false` | Stream output from jobs while they are running |
| `-FlushOnCompleted` | `switch` | `false` | Stream output from jobs when they complete |

### Add-RunspaceJob

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-Manager` | `PSCustomObject` | ✅ | The manager object from `New-RunspaceManager` |
| `-ScriptBlock` | `scriptblock` | ✅ | The code to run in the job |
| `-Arguments` | `object[]` | ❌ | Arguments passed to the script (queue is injected automatically as the last argument) |
| `-Label` | `string` | ❌ | Name shown in progress bar and error messages |

---

## 📌 Important Notes

The **last parameter** of your ScriptBlock must always be `$queue`.
It is injected automatically by `Add-RunspaceJob` — do not pass it manually.

```powershell
# Correct — $queue is the last param, not passed in -Arguments
$job = {
    param($arg1, $arg2, $queue)
    $queue.Enqueue("Done")
}
$mgr | Add-RunspaceJob -ScriptBlock $job -Arguments @("val1", "val2") -Label "MyJob"
```

---

## 📄 License

MIT License — feel free to use, modify, and distribute.
