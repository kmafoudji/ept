<?php

ini_set('memory_limit', '-1');

require_once __DIR__ . '/../cli-bootstrap.php';

$cliOptions = getopt("s:");
$shipmentToSendReport = $cliOptions['s'];


if (empty($shipmentToSendReport)) {
	Pt_Commons_LoggerUtility::logError("Please specify the shipment ids with the -s flag");
	exit();
}

if (is_array($shipmentToSendReport)) {
	$shipmentToSendReport = implode(",", $shipmentToSendReport);
} else {
	$shipmentToSendReport = array($shipmentToSendReport);
}


$conf = new Zend_Config_Ini(APPLICATION_PATH . '/configs/application.ini', APPLICATION_ENV);
$shipmentService = new Application_Service_Shipments();
$commonService = new Application_Service_Common();
try {

	$db = Zend_Db::factory($conf->resources->db);
	Zend_Db_Table::setDefaultAdapter($db);
	foreach ($shipmentToSendReport as $shipmentId) {
		$timeStart = microtime(true);
		$mailStats = null;
		$shipmentResult = $shipmentService->fetchReportsMail($shipmentId, $conf, $mailStats);
		$timeEnd = microtime(true);
		$executionTime = ($timeEnd - $timeStart) / 60;
		$shipmentCode = $shipmentResult[0]['shipment_code'] ?? (string) $shipmentId;
		$notSent = (int) $mailStats['not_sent'] + (int) $mailStats['missing_files'];
		// Say what really happened: the screen that started this job already
		// told the admin "sent", so the notification must carry the real count.
		$description = 'Shipment ' . $shipmentCode . ': report emails queued for ' . (int) $mailStats['queued'] . ' participant(s)';
		if ($notSent > 0) {
			$description .= ', NOT sent to ' . $notSent . ' (see Configure > Failed Emails and the log)';
		}
		$description .= ' in ' . round($executionTime, 2) . ' mins';
		$db->insert('notify', [
			'title' => $notSent > 0 ? 'Shipment Report Mail: some emails not sent' : 'Shipment Report Mail',
			'description' => $description,
			'link' => $notSent > 0 ? '/admin/alerts/email' : '/reports/finalize/shipments'
		]);
	}
} catch (Throwable $e) {
	Pt_Commons_LoggerUtility::logError($e->getMessage(), [
	    'file'  => $e->getFile(),
	    'line'  => $e->getLine(),
	    'trace' => $e->getTraceAsString(),
	]);
}
