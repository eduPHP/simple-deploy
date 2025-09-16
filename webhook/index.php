<?php
error_reporting(E_ALL);


require_once realpath(__DIR__.'/../vendor/autoload.php');

function logMessage($message) {
    file_put_contents(realpath(__DIR__.'/..').'/worker.log', date('Y-m-d H:i:s').": $message" . "\n", FILE_APPEND);
}

// Load environment variables from .env file
$env = parse_ini_file(realpath(__DIR__ . '/../.env'));

// Capture the raw POST body
$signature = $_SERVER['HTTP_X_DEPLOY_SECRET'] ?? '';

if ($signature !== $env['DEPLOY_SECRET']) {
  http_response_code(403);
  logMessage("❌ Invalid secret.\n");
  die;
}

$body = json_decode(file_get_contents('php://input'), true);

$message = "✅ Received " . date('Y-m-d H:i:s') . "\n";
foreach ($body as $key => $value) {
  $message .= "*{$key}*: {$value}\n";
}

$postData = [
    'sessionId' => $env['WA_SESSION_ID'],
    'to' => $env['WA_MESSAGE_JID_TO'],
    'message' => $message,
];

// save queue
$file = realpath(__DIR__.'/../queue').'/'.$body['commit'].'.json';
if (file_put_contents($file, json_encode($body), LOCK_EX)) {
  logMessage("✅ Saved to queue: $file");
} else {
  logMessage("❌ Error saving to queue");
  http_response_code(500);
  die;
}

try {
  // The data you want to send in the POST request (as an associative array)
  $client = new \GuzzleHttp\Client();
  $client->post($env['WA_WEBHOOK_URL'], [
      'json' => $postData,
  ]);
  logMessage("✅ Sent to WhatsApp API");
} catch (Exception $e) {
  // Handle exception if needed
  logMessage("❌ Error, check logs: " . $e->getMessage());
  http_response_code(500);
  die;
}
echo "🚀 Webhook received\n";
http_response_code(200);
