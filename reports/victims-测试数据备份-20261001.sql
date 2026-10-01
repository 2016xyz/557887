=== 备份 victims 全表（含字段结构） ===
-- MySQL dump 10.13  Distrib 8.0.46, for Linux (x86_64)
--
-- Host: localhost    Database: jasmin_db
-- ------------------------------------------------------
-- Server version	8.0.46

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Dumping data for table `victims`
--

LOCK TABLES `victims` WRITE;
/*!40000 ALTER TABLE `victims` DISABLE KEYS */;
INSERT INTO `victims` (`id`, `machine_name`, `computer_user`, `os`, `date`, `time`, `ip`, `location`, `systemid`, `password`, `encrypted_count`, `encrypted_size`, `encrypted_types`, `encrypted_detail`, `created_at`, `total_count`, `total_size`, `is_complete`, `updated_at`) VALUES (9,'localhost.localdomain','root','Linux 5.14.0-737.el9.x86_64','01/10/2026, Thursday','10:49:59','43.133.237.180','?','0x0-localhost.localdomain','RSA_PROTECTED',0,918206394,'','','2026-10-01 02:49:55',34033,1242568263,1,'2026-10-01 02:50:00'),(10,'28325c816f48','?','Linux 5.14.0-741.el9.x86_64','01/10/2026, Thursday','02:54:44','34.2.145.178','?','0x0-28325c816f48','RSA_PROTECTED',34033,1224797308,'.csv,.docx,.json,.md,.pdf,.png,.py,.sql,.txt,.zip','{\".pdf\": {\"count\": 3406, \"size\": 38071418}, \".py\": {\"count\": 3412, \"size\": 111482203}, \".csv\": {\"count\": 3422, \"size\": 74781923}, \".txt\": {\"count\": 3383, \"size\": 74756551}, \".png\": {\"count\": 3353, \"size\": 74752320}, \".md\": {\"count\": 3463, \"size\": 184893144}, \".json\": {\"count\": 3425, \"size\": 111490220}, \".sql\": {\"count\": 3446, \"size\": 221585133}, \".zip\": {\"count\": 3339, \"size\": 148133089}, \".docx\": {\"count\": 3384, \"size\": 184851307}}','2026-10-01 02:53:23',34033,1224797308,1,'2026-10-01 02:54:45'),(11,'vm-2-23984-1-4976','root','Linux 5.14.0-741.el9.x86_64','01/10/2026, Thursday','03:05:19','34.2.145.178','?','0x0-vm-2-23984-1-4976','RSA_PROTECTED',34033,204019639,'.csv,.docx,.json,.md,.pdf,.png,.sql,.txt','{\".md\": {\"count\": 4204, \"size\": 1868802}, \".csv\": {\"count\": 4168, \"size\": 1875659}, \".docx\": {\"count\": 4238, \"size\": 1885221}, \".png\": {\"count\": 4327, \"size\": 1965607}, \".json\": {\"count\": 4221, \"size\": 1924354}, \".txt\": {\"count\": 4233, \"size\": 190644411}, \".pdf\": {\"count\": 4336, \"size\": 1953563}, \".sql\": {\"count\": 4306, \"size\": 1902022}}','2026-10-01 02:55:14',34033,204019639,1,'2026-10-01 08:29:55'),(12,'vm-2-23184-1-4f7444ab','root','Linux 5.14.0-741.el9.x86_64','01/10/2026, Thursday','02:56:51','35.209.29.222','?','0x0-vm-2-23184-1-4f7444ab','RSA_PROTECTED',2,941,'.conf,.json','{\".conf\": {\"count\": 1, \"size\": 939}, \".json\": {\"count\": 1, \"size\": 2}}','2026-10-01 02:56:52',2,941,1,'2026-10-01 02:56:52');
/*!40000 ALTER TABLE `victims` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-10-01  8:32:09
