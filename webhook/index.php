<?php

error_reporting(0);

require_once __DIR__.'/../vendor/autoload.php';

// Load environment variables from .env file
$env = parse_ini_file(__DIR__.'/../.env');

// Capture the raw POST body
$signature = $_SERVER['HTTP_X_DEPLOY_SECRET'] ?? '';

if ($signature !== $env['DEPLOY_SECRET']) {
  http_response_code(403);
  echo "❌ Invalid secret.\n";
  die;
}

$body = json_decode(file_get_contents('php://input'), true);

$log = "✅ Ready " . date('Y-m-d H:i:s') . "\n";
foreach ($body as $key => $value) {
  $log .= "*{$key}*: {$value}\n";
}

$postData = [
    'sessionId' => $env['WA_SESSION_ID'],
    'to' => $env['WA_MESSAGE_JID_TO'],
    'message' => $log,
];

// The data you want to send in the POST request (as an associative array)
$client = new \GuzzleHttp\Client();
$response = $client->post($env['WA_WEBHOOK_URL'], [
    'json' => $postData,
]);

// save queue
$file = __DIR__ . '/../queue/'.$body['commit'].'.txt';
file_put_contents($file, json_encode($body), FILE_APPEND | LOCK_EX);

echo $response->getBody()->getContents();