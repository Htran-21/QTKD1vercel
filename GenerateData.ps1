# GenerateData.ps1 - Generates 120 synthetic contracts, usage logs, and tickets for An Tin Co.
param (
    [string]$ReconciliationDate = "2026-11-11"
)

$refDate = [DateTime]::Parse($ReconciliationDate)

$companyPrefixes = @("Công ty CP", "Công ty TNHH", "Tập đoàn", "Tổng Công ty", "Công ty Cổ phần Đầu tư")
$industries = @("Logistics Việt", "Công nghệ Số", "Bán lẻ An Khang", "Dược phẩm Á Châu", "Bất động sản Thịnh Vượng", 
               "Xây dựng Đại Tín", "Tài chính Toàn Cầu", "Sản xuất May mặc", "Nông nghiệp Xanh", "Thương mại Dịch vụ Nam Hải",
               "Vận tải Phương Nam", "Chuỗi Thực phẩm Tươi", "Phần mềm Trí Tuệ", "Giáo dục Quốc tế", "Y tế Thông minh",
               "Nội thất Hiện đại", "Thương mại Điện tử Vina", "Bảo hiểm Việt Nhật", "Kho vận Ánh Dương", "Thời trang Trẻ")

$salesReps = @("Nguyễn Văn Tuấn", "Trần Thị Mai", "Lê Hoàng Long", "Phạm Quốc Dũng", "Hoàng Thu Thảo", "Vũ Minh Đức")
$csReps = @("Đặng Ngọc Hà", "Bùi Thanh Hương", "Lê Tuấn Kiệt", "Trần Mai Anh", "Ngô Đức Huy")

$contracts = @()
$usageLogs = @()
$supportTickets = @()

$pkgDetails = @{
    "PKG-STD" = @{ Name = "Standard"; Price = 1440000; LeadDays = 30; MaxUsers = 20; Storage = 20 }
    "PKG-PRO" = @{ Name = "Professional"; Price = 2640000; LeadDays = 45; MaxUsers = 80; Storage = 100 }
    "PKG-ENT" = @{ Name = "Enterprise"; Price = 4560000; LeadDays = 60; MaxUsers = 9999; Storage = 500 }
}

for ($i = 1; $i -le 120; $i++) {
    $cid = "CUST-" + ($i.ToString("D4"))
    $contractId = "HD-AT-2025-" + ($i.ToString("D4"))
    $companyName = $companyPrefixes[($i * 7) % $companyPrefixes.Length] + " " + $industries[($i * 3) % $industries.Length] + " " + (100 + $i)
    
    # Assign package tier
    if ($i -le 40) {
        $pkgId = "PKG-STD"
        $regSeats = [Math]::Max(5, (10 + ($i % 11))) # 5 to 20
    } elseif ($i -le 95) {
        $pkgId = "PKG-PRO"
        $regSeats = [Math]::Max(15, (20 + ($i % 55))) # 20 to 74
    } else {
        $pkgId = "PKG-ENT"
        $regSeats = [Math]::Max(50, (60 + ($i % 150))) # 60 to 209
    }
    
    $pkg = $pkgDetails[$pkgId]
    $leadDays = $pkg.LeadDays
    
    # Expiration dates around Dec 2026 - Jan 2027 (e.g. 15 to 75 days after reconciliation date)
    $daysToExpiry = 15 + ($i % 60)
    $endDate = $refDate.AddDays($daysToExpiry)
    $startDate = $endDate.AddYears(-1)
    $contactStartDate = $endDate.AddDays(-$leadDays)
    
    $salesRep = $salesReps[$i % $salesReps.Length]
    $csRep = $csReps[$i % $csReps.Length]
    $currentVal = $regSeats * $pkg.Price
    
    # Customer scenario categorization:
    # 1. Unresolved Incident (Open Critical / Major tickets) -> Must NOT upsell
    # 2. Ineligible Discount Proposed -> Violates policy
    # 3. Underutilized / Low Adoption -> Registered 50, Active 8
    # 4. High Adoption / Upsell Candidate -> Registered 20, Active 20, Max storage
    # 5. Overdue Outreach -> RefDate > ContactStartDate
    # 6. Normal Healthy
    
    $scenario = "NORMAL_RENEW"
    $activeRatio = 0.85
    $openTicketsCount = 0
    $hasCriticalTicket = $false
    $proposedDiscountPercent = 0
    $proposedDiscountCode = "NONE"
    $proposedPackageId = $pkgId
    
    if ($i % 6 -eq 1) {
        # SCENARIO 1: OPEN CRITICAL / HIGH TICKET
        $scenario = "OPEN_INCIDENT_CHURN_RISK"
        $activeRatio = 0.70
        $openTicketsCount = 1 + ($i % 2)
        $hasCriticalTicket = $true
        # Human sales erroneously proposed upsell in legacy practice!
        $proposedPackageId = if ($pkgId -eq "PKG-STD") { "PKG-PRO" } elseif ($pkgId -eq "PKG-PRO") { "PKG-ENT" } else { "PKG-ENT" }
    } elseif ($i % 6 -eq 2) {
        # SCENARIO 2: LOW ADOPTION (Misunderstanding Registered vs Active Users)
        $scenario = "LOW_ADOPTION_DOWNSELL_RISK"
        $activeRatio = [Math]::Round(0.18 + (($i % 10) * 0.02), 2) # 18% to 36%
        $proposedPackageId = $pkgId
    } elseif ($i % 6 -eq 3) {
        # SCENARIO 3: INELIGIBLE DISCOUNT (Rule violation by human sales)
        $scenario = "INELIGIBLE_PROMO_ATTEMPTED"
        $activeRatio = 0.82
        $proposedDiscountPercent = 20 # Human gave 20% without meeting 3Y commitment or volume
        $proposedDiscountCode = "DISC_MULTI_YEAR_3Y_UNVERIFIED"
    } elseif ($i % 6 -eq 4) {
        # SCENARIO 4: OVERDUE OUTREACH (Confusing End Date with Contact Start Date)
        $scenario = "OVERDUE_CONTACT_DATE"
        $daysToExpiry = 20 + ($i % 10) # e.g. 25 days left, but Pro lead is 45 days -> already 20 days overdue!
        $endDate = $refDate.AddDays($daysToExpiry)
        $contactStartDate = $endDate.AddDays(-$leadDays)
        $activeRatio = 0.90
    } elseif ($i % 6 -eq 5) {
        # SCENARIO 5: HEALTHY HIGH ADOPTION (Legitimate Upsell Opportunity)
        $scenario = "HIGH_ADOPTION_UPSELL_READY"
        $activeRatio = 0.98
        $proposedPackageId = if ($pkgId -eq "PKG-STD") { "PKG-PRO" } elseif ($pkgId -eq "PKG-PRO") { "PKG-ENT" } else { "PKG-ENT" }
        $proposedDiscountPercent = 10
        $proposedDiscountCode = "DISC_EARLY_BIRD"
    } else {
        # SCENARIO 6: STABLE STANDARD RENEWAL
        $scenario = "STABLE_RENEW"
        $activeRatio = 0.80
        $proposedDiscountPercent = 5
        $proposedDiscountCode = "DISC_LOYALTY"
    }
    
    $activeUsers = [Math]::Max(1, [int][Math]::Round($regSeats * $activeRatio))
    $storageUsedGb = [Math]::Round(($pkg.Storage * ($activeRatio * 0.9 + 0.05)), 1)
    $dauMauRatio = [Math]::Round(0.55 + ($activeRatio * 0.35), 2)
    $logins30d = $activeUsers * (15 + ($i % 12))
    
    # Contract record
    $contractObj = [PSCustomObject]@{
        customer_id = $cid
        contract_id = $contractId
        company_name = $companyName
        tax_id = "010" + (8000000 + $i)
        signer_name = "Giám đốc " + ($companyName.Split(' ')[-2] + " " + $companyName.Split(' ')[-1])
        contact_email = "contact" + $i + "@" + ($industries[($i * 3) % $industries.Length].ToLower() -replace '[^a-z0-9]','') + ".vn"
        contact_phone = "098" + (1000000 + $i)
        current_package_id = $pkgId
        current_package_name = $pkg.Name
        registered_seats = $regSeats
        annual_contract_value = $currentVal
        contract_start_date = $startDate.ToString("yyyy-MM-dd")
        contract_end_date = $endDate.ToString("yyyy-MM-dd")
        contact_start_date = $contactStartDate.ToString("yyyy-MM-dd")
        lead_time_days = $leadDays
        sales_rep = $salesRep
        cs_rep = $csRep
        tenure_years = 1 + ($i % 4)
        legacy_human_proposed_package = $proposedPackageId
        legacy_human_proposed_discount_pct = $proposedDiscountPercent
        legacy_human_proposed_promo_code = $proposedDiscountCode
    }
    $contracts += $contractObj
    
    # Usage log record
    $usageObj = [PSCustomObject]@{
        customer_id = $cid
        contract_id = $contractId
        reconciliation_date = $ReconciliationDate
        registered_seats = $regSeats
        active_users_30d = $activeUsers
        seat_utilization_pct = [Math]::Round(($activeUsers / $regSeats) * 100, 1)
        dau_mau_ratio = $dauMauRatio
        total_logins_30d = $logins30d
        storage_quota_gb = $pkg.Storage
        storage_used_gb = $storageUsedGb
        storage_utilization_pct = [Math]::Round(($storageUsedGb / $pkg.Storage) * 100, 1)
        key_features_used_count = if ($pkgId -eq "PKG-ENT") { 18 } elseif ($pkgId -eq "PKG-PRO") { 12 } else { 6 }
        usage_trend = if ($activeRatio -ge 0.85) { "Tăng trưởng (+15%)" } elseif ($activeRatio -le 0.40) { "Sụt giảm mạnh (-35%)" } else { "Ổn định" }
    }
    $usageLogs += $usageObj
    
    # Support tickets
    if ($openTicketsCount -gt 0) {
        for ($t = 1; $t -le $openTicketsCount; $t++) {
            $ticketId = "TK-" + $cid + "-0" + $t
            $severity = if ($t -eq 1 -and $hasCriticalTicket) { "CRITICAL" } else { "HIGH" }
            $ticketObj = [PSCustomObject]@{
                ticket_id = $ticketId
                customer_id = $cid
                contract_id = $contractId
                category = if ($severity -eq "CRITICAL") { "Lỗi hệ thống (System Outage / Data Sync)" } else { "Tích hợp API & Báo cáo" }
                severity = $severity
                status = if ($i % 2 -eq 0) { "IN_PROGRESS" } else { "OPEN" }
                created_date = $refDate.AddDays(- (3 + $t)).ToString("yyyy-MM-dd")
                resolved_date = $null
                sla_hours = 8
                sla_breached = $true
                csat_rating = 2.0
                summary = "Sự cố đồng bộ dữ liệu hóa đơn điện tử bị gián đoạn và báo lỗi timeout liên tục."
                assigned_tech = "Kỹ thuật viên Nguyễn Hoàng Nam"
            }
            $supportTickets += $ticketObj
        }
    } else {
        # Normal customer ticket history (either resolved or 0)
        if ($i % 3 -eq 0) {
            $ticketId = "TK-" + $cid + "-HIST"
            $ticketObj = [PSCustomObject]@{
                ticket_id = $ticketId
                customer_id = $cid
                contract_id = $contractId
                category = "Hướng dẫn sử dụng & Cấu hình"
                severity = "NORMAL"
                status = "RESOLVED"
                created_date = $refDate.AddDays(-25).ToString("yyyy-MM-dd")
                resolved_date = $refDate.AddDays(-24).ToString("yyyy-MM-dd")
                sla_hours = 24
                sla_breached = $false
                csat_rating = 4.8
                summary = "Hỗ trợ phân quyền người dùng và xuất báo cáo doanh số chi nhánh."
                assigned_tech = "Kỹ thuật viên Phạm Minh Quân"
            }
            $supportTickets += $ticketObj
        }
    }
}

# Write files
$contracts | ConvertTo-Json -Depth 5 | Set-Content -Path "data/contracts.json" -Encoding UTF8
$contracts | Export-Csv -Path "data/contracts.csv" -NoTypeInformation -Encoding UTF8

$usageLogs | ConvertTo-Json -Depth 5 | Set-Content -Path "data/usage_logs.json" -Encoding UTF8
$usageLogs | Export-Csv -Path "data/usage_logs.csv" -NoTypeInformation -Encoding UTF8

$supportTickets | ConvertTo-Json -Depth 5 | Set-Content -Path "data/support_tickets.json" -Encoding UTF8
$supportTickets | Export-Csv -Path "data/support_tickets.csv" -NoTypeInformation -Encoding UTF8

Write-Host "Generated 120 Contracts, Usage Logs, and Support Tickets successfully."

