use axum_server::Handle;
use tokio::signal;
use tokio::time::{sleep, Duration, Instant};
use tracing::{info, warn};

static SIGINT: &str = "Ctrl+C";
static SIGTERM: &str = "SIGTERM";
const GRACE_DURATION: u64 = 3; // seconds
const CHECK_INTERVAL: u64 = 30; // seconds
const IDLE_DURATION: Duration = Duration::from_secs(300);

pub async fn monitor(handle: Handle) {
    tokio::select! {
        _ = ctrl_c() => grace_shutdown(&handle, SIGINT),
        _ = terminate() => grace_shutdown(&handle, SIGTERM),
        _ = check_idle(&handle) => {}
    }
}

async fn ctrl_c() {
    signal::ctrl_c()
        .await
        .expect("failed to install Ctrl+C handler");
}

async fn terminate() {
    #[cfg(unix)]
    signal::unix::signal(signal::unix::SignalKind::terminate())
        .expect("failed to install signal handler")
        .recv()
        .await;

    #[cfg(not(unix))]
    std::future::pending::<()>();
}

fn grace_shutdown(handle: &Handle, signal: &str) {
    warn!("Received {}, shutting down...", signal);
    handle.graceful_shutdown(Some(Duration::from_secs(GRACE_DURATION)));
}

// to be checked by the connection type of client/serveer protocol
// we assume that a client keeps connection open when it is running
// therefore the number of connection is a reliable metric to check activities
async fn check_idle(handle: &Handle) {
    let mut last_activity = Instant::now();
    loop {
        let count = handle.connection_count();
        if count > 0 {
            info!("Current connection count: {count}");
            last_activity = Instant::now();
        } else {
            let idle_time = last_activity.elapsed();
            info!("Idle for {:?}", idle_time);
            if idle_time > IDLE_DURATION {
                info!("Shutdown after being idle longer than {:?}", IDLE_DURATION);
                handle.shutdown();
            }
        }
        sleep(Duration::from_secs(CHECK_INTERVAL)).await;
    }
}
