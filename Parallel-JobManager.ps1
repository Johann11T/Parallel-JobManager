function New-RunspaceManager {
    param(
        [int]$MaxConcurrent          = 25,
        [switch]$FlushOnRunning,
        [switch]$FlushOnCompleted
    )
    # Create and open the shared runspace pool
    $pool = [runspacefactory]::CreateRunspacePool($MaxConcurrent, $MaxConcurrent)
    $pool.Open()

    return [PSCustomObject]@{
        Pool             = $pool
        Jobs             = [System.Collections.Generic.List[hashtable]]::new()
        MaxSlots         = $MaxConcurrent
        Total            = 0
        Completed        = 0
        FlushOnRunning   = $FlushOnRunning.IsPresent
        FlushOnCompleted = $FlushOnCompleted.IsPresent
    }
}

function Add-RunspaceJob {
    param(
        [Parameter(Mandatory, ValueFromPipeline)][PSCustomObject]$Manager,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [object[]]$Arguments = @(),
        [string]$Label = ''
    )
    # Block until a slot is free, draining output while waiting
    while ($Manager.Jobs.Count -ge $Manager.MaxSlots) {
        Start-Sleep -Milliseconds 100
        Drain-RunningQueues $Manager
        Clear-CompletedJobs $Manager
    }

    $Manager.Total++

    # Each job gets its own queue — injected automatically as the last argument
    $jobQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()

    $ps = [powershell]::Create()
    $ps.RunspacePool = $Manager.Pool
    $ps.AddScript($ScriptBlock) | Out-Null
    foreach ($arg in $Arguments) { $ps.AddArgument($arg) | Out-Null }
    $ps.AddArgument($jobQueue) | Out-Null

    $Manager.Jobs.Add(@{
        PS     = $ps
        Result = $ps.BeginInvoke()
        Label  = $Label
        Queue  = $jobQueue
    })

    Write-Progress -Id 0 -Activity "Runspace Jobs" `
        -Status "Queued: $($Manager.Total) | Completed: $($Manager.Completed) | Running: $($Manager.Jobs.Count)" `
        -PercentComplete ([math]::Min(99, ($Manager.Completed / [math]::Max(1, $Manager.Total) * 100)))
}

# Dequeues and prints all pending messages from a single job's queue
function Drain-JobQueue {
    param([hashtable]$job)

    $msg = $null
    while ($job.Queue.TryDequeue([ref]$msg)) {
        if ($msg -is [PSCustomObject] -and $msg.PSObject.Properties['Color']) {
            Write-Host $msg.Message -ForegroundColor $msg.Color
        } else {
            Write-Host $msg
        }
    }
}

# Drains queues of all currently running jobs (used by -FlushOnRunning)
function Drain-RunningQueues {
    param([PSCustomObject]$Manager)

    if (-not $Manager.FlushOnRunning) { return }

    foreach ($job in ($Manager.Jobs | Where-Object { $_.PS.InvocationStateInfo.State -eq 'Running' })) {
        Drain-JobQueue $job
    }
}

# Flushes Warning and Error streams after a job finishes
function Flush-JobStreams {
    param([hashtable]$job)

    foreach ($msg in $job.PS.Streams.Warning.ReadAll()) { Write-Warning "[$($job.Label)] $msg" }

    foreach ($msg in $job.PS.Streams.Error.ReadAll()) { Write-Host "[ERROR][$($job.Label)] $msg" -ForegroundColor Red }
}

function Clear-CompletedJobs {
    param([PSCustomObject]$Manager)

    $done = $Manager.Jobs | Where-Object {
        $_.PS.InvocationStateInfo.State -in 'Completed', 'Failed', 'Stopped'
    } | ForEach-Object { $_ }

    foreach ($job in $done) {
        # Final drain to capture any messages written before the job ended
        if ($Manager.FlushOnRunning -or $Manager.FlushOnCompleted) {
            Drain-JobQueue $job
        }

        Flush-JobStreams $job

        try {
            $job.PS.EndInvoke($job.Result)
        } catch {
            Write-Host "[ERROR][$($job.Label)] $_" -ForegroundColor Red
        }

        if ($job.PS.InvocationStateInfo.State -eq 'Failed') {
            Write-Host "[FAILED][$($job.Label)] $($job.PS.InvocationStateInfo.Reason)" -ForegroundColor Red
        }

        $job.PS.Dispose()
        $Manager.Jobs.Remove($job) | Out-Null
        $Manager.Completed++

        Write-Progress -Id 0 -Activity "Runspace Jobs" `
            -Status "Queued: $($Manager.Total) | Completed: $($Manager.Completed) | Running: $($Manager.Jobs.Count)" `
            -PercentComplete ([math]::Min(99, ($Manager.Completed / [math]::Max(1, $Manager.Total) * 100)))

        Write-Progress -Id 1 -Activity "Last completed" -Status $job.Label -PercentComplete 100
    }

    # Drain running jobs after processing completed ones
    Drain-RunningQueues $Manager
}

function Wait-RunspaceManager {
    param([Parameter(Mandatory, ValueFromPipeline)][PSCustomObject]$Manager)

    # Poll until all jobs are done
    while ($Manager.Jobs.Count -gt 0) {
        Start-Sleep -Milliseconds 200
        Drain-RunningQueues $Manager
        Clear-CompletedJobs $Manager
    }

    $Manager.Pool.Close()
    $Manager.Pool.Dispose()

    Write-Progress -Id 1 -Activity "Last completed" -Completed
    Write-Progress -Id 0 -Activity "Runspace Jobs"  -Completed
}
