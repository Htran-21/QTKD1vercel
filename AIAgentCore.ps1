<#
    AIAgentCore.ps1 - Hệ thống AI Agent Tự Động Hóa Quy Trình Gia Hạn Hợp Đồng - Công ty An Tín
    Xử lý 4 bước theo sơ đồ quy trình:
    Bước 1: Thu thập & Tổng hợp dữ liệu tự động, Gắn nhãn khách hàng
    Bước 2: AI Phân tích & Đánh giá (Mức sử dụng, Tồn đọng hỗ trợ, Đề xuất gói & ưu đãi hợp lệ, Soạn bản nháp)
    Bước 3: Phối hợp xử lý và điều chỉnh (CS + Sales + AI Agent)
    Bước 4: Trưởng phòng phê duyệt (Approve/Reject + Action logs)
#>

function Invoke-AnTinAIAgentPipeline {
    param (
        [string]$DataDir = "data",
        [string]$OutputDir = "output"
    )

    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "  HỆ THỐNG AI AGENT ĐỀ XUẤT GIA HẠN HỢP ĐỒNG - CÔNG TY AN TÍN" -ForegroundColor Cyan
    Write-Host "======================================================================" -ForegroundColor Cyan

    # Đọc dữ liệu đầu vào
    $reconcilePath = Join-Path $DataDir "reconciliation_date.json"
    $policyPath = Join-Path $DataDir "service_catalog_and_policies.json"
    $contractsPath = Join-Path $DataDir "contracts.json"
    $usagePath = Join-Path $DataDir "usage_logs.json"
    $ticketsPath = Join-Path $DataDir "support_tickets.json"

    if (-not (Test-Path $reconcilePath) -or -not (Test-Path $contractsPath)) {
        Write-Error "Không tìm thấy đủ tệp dữ liệu đầu vào trong thư mục $DataDir"
        return $null
    }

    $reconciliationInfo = Get-Content $reconcilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $policies = Get-Content $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $contracts = Get-Content $contractsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $usageLogs = Get-Content $usagePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $tickets = Get-Content $ticketsPath -Raw -Encoding UTF8 | ConvertFrom-Json

    $reconcileDate = [DateTime]::Parse($reconciliationInfo.reconciliation_date)
    Write-Host "[BƯỚC 1] Khởi chạy Thu thập & Hợp nhất Dữ liệu tự động..." -ForegroundColor Yellow
    Write-Host "  -> Ngày đối chiếu chuẩn: $($reconcileDate.ToString('yyyy-MM-dd'))" -ForegroundColor Gray
    Write-Host "  -> Tổng số hợp đồng cần rà soát: $($contracts.Count)" -ForegroundColor Gray

    # Tạo chỉ mục tra cứu nhanh
    $usageMap = @{}
    foreach ($u in $usageLogs) {
        $usageMap[$u.customer_id] = $u
    }

    $ticketsMap = @{}
    foreach ($t in $tickets) {
        if (-not $ticketsMap.ContainsKey($t.customer_id)) {
            $ticketsMap[$t.customer_id] = @()
        }
        $ticketsMap[$t.customer_id] += $t
    }

    $catalogMap = @{}
    foreach ($pkg in $policies.service_catalog) {
        $catalogMap[$pkg.package_id] = $pkg
    }

    $masterDossiers = @()

    foreach ($c in $contracts) {
        $cid = $c.customer_id
        $usage = $usageMap[$cid]
        $custTickets = if ($ticketsMap.ContainsKey($cid)) { $ticketsMap[$cid] } else { @() }
        
        $expiryDate = [DateTime]::Parse($c.contract_end_date)
        $contactDate = [DateTime]::Parse($c.contact_start_date)

        $daysToExpiry = [int]($expiryDate - $reconcileDate).TotalDays
        $daysToContact = [int]($contactDate - $reconcileDate).TotalDays

        # Timeline status
        $timelineStatus = "CHUẨN BỊ"
        $timelineBadge = "info"
        if ($daysToExpiry -le 0) {
            $timelineStatus = "HẾT HẠN HỢP ĐỒNG"
            $timelineBadge = "danger"
        } elseif ($daysToContact -lt 0) {
            $timelineStatus = "QUÁ HẠN BẮT ĐẦU LIÊN HỆ"
            $timelineBadge = "danger"
        } elseif ($daysToContact -le 7) {
            $timelineStatus = "CẦN LIÊN HỆ TRONG TUẦN"
            $timelineBadge = "warning"
        } else {
            $timelineStatus = "ĐÚNG KẾ HOẠCH"
            $timelineBadge = "success"
        }

        # BƯỚC 2: AI PHÂN TÍCH VÀ ĐÁNH GIÁ
        # 1. Đánh giá mức độ sử dụng (Tránh nhầm lẫn Số TK đăng ký vs Số người thực tế dùng)
        $regSeats = [int]$c.registered_seats
        $activeSeats = if ($usage) { [int]$usage.active_users_30d } else { [Math]::Max(1, [int]($regSeats * 0.7)) }
        $activationPct = [Math]::Round(($activeSeats / $regSeats) * 100, 1)
        $storagePct = if ($usage) { [double]$usage.storage_utilization_pct } else { 50.0 }
        $usageTrend = if ($usage) { $usage.usage_trend } else { "Ổn định" }

        # 2. Kiểm tra tồn đọng hỗ trợ
        $openTickets = @($custTickets | Where-Object { $_.status -in @("OPEN", "IN_PROGRESS") })
        $criticalTickets = @($openTickets | Where-Object { $_.severity -in @("CRITICAL", "HIGH") })
        $hasUnresolvedIncident = ($criticalTickets.Count -gt 0)
        
        $avgCsat = 4.5
        $csatTickets = @($custTickets | Where-Object { $_.csat_rating -gt 0 })
        if ($csatTickets.Count -gt 0) {
            $sum = 0
            foreach ($st in $csatTickets) { $sum += [double]$st.csat_rating }
            $avgCsat = [Math]::Round(($sum / $csatTickets.Count), 1)
        }

        # 3. Tính Health Score (0 - 100)
        # 40% Usage + 30% Support/CSAT + 30% Contract/Timeline
        $usageScore = [Math]::Min(40, [Math]::Max(0, ($activationPct / 100.0) * 40))
        $supportScore = if ($hasUnresolvedIncident) { 5 } elseif ($openTickets.Count -gt 0) { 15 } else { 30 }
        $csatScore = ($avgCsat / 5.0) * 30
        $healthScore = [int][Math]::Round($usageScore + ($supportScore * 0.5 + $csatScore * 0.5))

        # Phân loại & Gắn nhãn Khách hàng
        $tags = @()
        $riskLevel = "LOW"
        
        if ($hasUnresolvedIncident) {
            $tags += "SỰ CỐ CHƯA XỬ LÝ (TỒN ĐỌNG)"
            $riskLevel = "HIGH"
        }
        if ($activationPct -lt 50.0) {
            $tags += "MỨC DÙNG THẤP (NGUY CƠ CHURN)"
            $riskLevel = "HIGH"
        } elseif ($activationPct -ge 85.0 -and $storagePct -ge 80.0) {
            $tags += "TIỀM NĂNG TĂNG GÓI (UPSELL)"
        }
        if ($daysToContact -lt 0) {
            $tags += "CHẬM TIẾN ĐỘ LIÊN HỆ"
        }
        if ($tags.Count -eq 0) {
            $tags += "HOẠT ĐỘNG ỔN ĐỊNH"
        }

        # 4. Tính toán đề xuất gói gia hạn & Kiểm tra vi phạm chính sách
        $currentPkgId = $c.current_package_id
        $currentPkg = $catalogMap[$currentPkgId]
        $recommendedPkgId = $currentPkgId
        $recommendedSeats = $regSeats
        $recommendationType = "RENEW_AS_IS"
        $recommendationRationale = ""
        $violations = @()

        # Kiểm tra logic tăng gói:
        # LỖI BỊ CHẶN: Nhân viên đề xuất tăng gói khi khách còn sự cố chưa xử lý
        $humanProposedPkg = $c.legacy_human_proposed_package
        if ($hasUnresolvedIncident -and $humanProposedPkg -ne $currentPkgId) {
            $violations += "VI PHẠM: Đề xuất tăng gói trong khi khách hàng có $($criticalTickets.Count) sự cố mức độ Critical/High chưa được xử lý dứt điểm!"
        }

        if ($hasUnresolvedIncident) {
            $recommendedPkgId = $currentPkgId
            $recommendationType = "HOLD_AND_RECOVER"
            $recommendationRationale = "ƯU TIÊN KHẨN CẤP: CS phối hợp bộ phận Hỗ trợ giải quyết dứt điểm ticket tồn đọng trước khi đề xuất gói. Tạm thời giữ nguyên gói hiện tại kèm cam kết SLA để tránh mất khách."
        } elseif ($activationPct -lt 50.0) {
            $recommendedPkgId = $currentPkgId
            $recommendationType = "DOWNSELL_OR_COACH"
            $recommendedSeats = [Math]::Max(5, [int][Math]::Ceiling($activeSeats * 1.2))
            $recommendationRationale = "CẢNH BÁO MỨC DÙNG THẤP: Khách chỉ kích hoạt $activeSeats/$regSeats tài khoản ($activationPct%). CS cần liên hệ đào tạo lại tính năng hoặc chủ động đề xuất tối ưu xuống $recommendedSeats tài khoản để giữ chân khách hàng."
        } elseif ($activationPct -ge 85.0 -and $storagePct -ge 80.0 -and -not $hasUnresolvedIncident) {
            # Đủ điều kiện nâng gói
            if ($currentPkgId -eq "PKG-STD") {
                $recommendedPkgId = "PKG-PRO"
                $recommendationType = "UPGRADE_PACKAGE"
                $recommendationRationale = "CƠ HỘI NÂNG GÓI: Khách sử dụng kịch trần tài khoản ($activeSeats/$regSeats) và dung lượng ($storagePct%). Đề xuất nâng lên Professional để mở khóa tự động hóa và tích hợp API."
            } elseif ($currentPkgId -eq "PKG-PRO" -and $regSeats -ge 40) {
                $recommendedPkgId = "PKG-ENT"
                $recommendationType = "UPGRADE_PACKAGE"
                $recommendationRationale = "CƠ HỘI NÂNG GÓI ENTERPRISE: Khách hàng tăng trưởng mạnh mẽ, khuyến nghị nâng cấp lên Enterprise để có CS Dedicated và bảo mật SSO nâng cao."
            } else {
                $recommendedSeats = [int][Math]::Ceiling($regSeats * 1.25)
                $recommendationType = "ADD_SEATS"
                $recommendationRationale = "CƠ HỘI MUA THÊM TÀI KHOẢN: Tỷ lệ hoạt động đạt $activationPct%. Khuyến nghị bổ sung thêm $recommendedSeats - $regSeats seats cho phòng ban mới."
            }
        } else {
            $recommendedPkgId = $currentPkgId
            $recommendationType = "RENEW_STANDARD"
            $recommendationRationale = "GIA HẠN ỔN ĐỊNH: Khách hàng duy trì mức sử dụng tốt ($activationPct%), CSAT cao, đề xuất gia hạn 12 tháng tiếp theo."
        }

        # Kiểm tra điều kiện ưu đãi (Discount Policy Compliance)
        $humanProposedDiscountPct = [int]$c.legacy_human_proposed_discount_pct
        $humanPromoCode = $c.legacy_human_proposed_promo_code
        $validDiscountPct = 0
        $appliedPromoCodes = @()

        # Kiểm tra Early bird
        if ($daysToExpiry -ge 30 -and -not $hasUnresolvedIncident) {
            $validDiscountPct += 10
            $appliedPromoCodes += "DISC_EARLY_BIRD"
        }
        # Thâm niên >= 2 năm
        if ([int]$c.tenure_years -ge 2 -and -not $hasUnresolvedIncident) {
            $validDiscountPct += 5
            $appliedPromoCodes += "DISC_LOYALTY"
        }
        # Volume
        if ($recommendedSeats -ge 50) {
            $validDiscountPct += 10
            $appliedPromoCodes += "DISC_VOLUME_50"
        } elseif ($recommendedSeats -ge 30) {
            $validDiscountPct += 5
            $appliedPromoCodes += "DISC_VOLUME_30"
        }

        # Khống chế trần
        if ($validDiscountPct -gt $policies.compliance_rules.max_allowed_discount_percent) {
            $validDiscountPct = $policies.compliance_rules.max_allowed_discount_percent
        }

        # Bắt lỗi nhân viên áp dụng ưu đãi sai
        if ($humanProposedDiscountPct -gt 0) {
            if ($c.annual_contract_value -lt $policies.compliance_rules.min_contract_value_for_discount) {
                $violations += "VI PHẠM: Hợp đồng giá trị nhỏ (< 15 triệu VNĐ) không được áp dụng chiết khấu!"
            }
            if ($humanProposedDiscountPct -gt $validDiscountPct) {
                $violations += "VI PHẠM ƯU ĐÃI: Nhân viên tự ý áp dụng chiết khấu $humanProposedDiscountPct% vượt quá mức chính sách cho phép ($validDiscountPct%)!"
            }
        }

        # Tính toán giá trị hợp đồng đề xuất
        $targetPkg = $catalogMap[$recommendedPkgId]
        $grossVal = $recommendedSeats * $targetPkg.annual_price_per_user
        $discountAmount = [Math]::Round($grossVal * ($validDiscountPct / 100.0))
        $proposedContractValue = $grossVal - $discountAmount
        $revenueDelta = $proposedContractValue - $c.annual_contract_value

        # Soạn thảo Bản nháp Trao đổi (Email / Script cá nhân hóa)
        $draftSubject = ""
        $draftBody = ""
        $contactPerson = $c.signer_name

        if ($hasUnresolvedIncident) {
            $draftSubject = "[An Tín Software] Thư đồng hành và cam kết hỗ trợ xử lý dứt điểm sự cố - $($c.company_name)"
            $draftBody = "Kính gửi $contactPerson,`n`nĐội ngũ Ban Giám đốc và Chăm sóc Khách hàng An Tín xin gửi lời xin lỗi chân thành về sự cố gián đoạn dịch vụ liên quan đến '$($criticalTickets[0].category)' mà Quý công ty đang gặp phải.`n`nChúng tôi đã cử Trưởng nhóm Kỹ thuật ưu tiên xử lý khắc phục trong vòng 4 giờ tới. Về kỳ gia hạn hợp đồng sắp tới, An Tín xin cam kết giữ nguyên các chính sách dịch vụ hiện tại và áp dụng gói bảo trợ kỹ thuật đặc biệt cho Quý công ty.`n`nChuyên viên CS phụ trách: $($c.cs_rep) - Hotline: 1900-ANTIN."
        } elseif ($activationPct -lt 50.0) {
            $draftSubject = "[An Tín Software] Chương trình tối ưu hiệu quả sử dụng phần mềm & Gói gia hạn linh hoạt - $($c.company_name)"
            $draftBody = "Kính gửi $contactPerson,`n`nQua rà soát số liệu định kỳ tại An Tín, chúng tôi nhận thấy hiện có $activeSeats trên tổng số $regSeats tài khoản đăng ký đang hoạt động thường xuyên. Để giúp Quý công ty tối ưu hóa chi phí và phát huy tối đa giá trị phần mềm, An Tín trân trọng kính mời đội ngũ tham gia buổi đào tạo tính năng nâng cao (miễn phí), đồng thời đề xuất gói gia hạn linh hoạt $recommendedSeats tài khoản giúp tiết kiệm ngân sách năm tới.`n`nChuyên viên CS $($c.cs_rep) sẽ liên hệ trong ngày hôm nay để hỗ trợ trực tiếp."
        } elseif ($recommendationType -eq "UPGRADE_PACKAGE") {
            $draftSubject = "[An Tín Software] Đề xuất nâng cấp giải pháp $($targetPkg.package_name) nhân dịp gia hạn - $($c.company_name)"
            $draftBody = "Kính gửi $contactPerson,`n`nChúc mừng Quý công ty đã có một năm tăng trưởng ấn tượng với tỷ lệ khai thác phần mềm đạt $activationPct%. Để đáp ứng nhu cầu mở rộng quy trình và tự động hóa toàn diện, An Tín trân trọng gửi tới Quý công ty đề xuất nâng cấp lên gói $($targetPkg.package_name) với ưu đãi Gia hạn sớm $validDiscountPct% dành riêng cho khách hàng tiêu biểu.`n`nChuyên viên Kinh doanh $($c.sales_rep) sẵn sàng gửi bản demo chi tiết tính năng."
        } else {
            $draftSubject = "[An Tín Software] Thông báo kế hoạch gia hạn hợp đồng dịch vụ phần mềm - $($c.company_name)"
            $draftBody = "Kính gửi $contactPerson,`n`nHợp đồng dịch vụ phần mềm số $($c.contract_id) của Quý công ty sẽ đến kỳ gia hạn vào ngày $($expiryDate.ToString('dd/MM/yyyy')). Để đảm bảo dịch vụ vận hành liên tục không gián đoạn, An Tín trân trọng gửi bảng chào giá gia hạn gói $($c.current_package_name) với chính sách ưu đãi Early Bird $validDiscountPct% khi xác nhận trước ngày $(($contactDate.AddDays(15)).ToString('dd/MM/yyyy')).`n`nTrân trọng cảm ơn sự tin tưởng của Quý khách hàng."
        }

        # Trạng thái hồ sơ trong quy trình 4 bước
        # Bước 3: Đã rà soát hay chưa
        $step3Status = if ($violations.Count -gt 0 -or $hasUnresolvedIncident) { "CẦN ĐIỀU CHỈNH (CS & SALES)" } else { "ĐÃ ĐỒNG THUẬN (SẴN SÀNG TRÌNH DUYỆT)" }
        $managerDecision = if ($violations.Count -gt 0 -or $hasUnresolvedIncident) { "PENDING_REVIEW" } else { "READY_FOR_APPROVAL" }

        $dossier = [PSCustomObject]@{
            customer_id = $cid
            contract_id = $c.contract_id
            company_name = $c.company_name
            tax_id = $c.tax_id
            signer_name = $contactPerson
            contact_email = $c.contact_email
            contact_phone = $c.contact_phone
            sales_rep = $c.sales_rep
            cs_rep = $c.cs_rep
            tenure_years = $c.tenure_years

            # Mốc ngày tháng & Timeline
            contract_start_date = $c.contract_start_date
            contract_end_date = $c.contract_end_date
            contact_start_date = $c.contact_start_date
            reconciliation_date = $reconciliationInfo.reconciliation_date
            days_to_expiry = $daysToExpiry
            days_to_contact_start = $daysToContact
            timeline_status = $timelineStatus
            timeline_badge = $timelineBadge

            # Phân tích mức độ sử dụng
            registered_seats = $regSeats
            active_users_30d = $activeSeats
            activation_rate_pct = $activationPct
            storage_utilization_pct = $storagePct
            usage_trend = $usageTrend
            health_score = $healthScore
            risk_level = $riskLevel
            customer_tags = ($tags -join ", ")

            # Phân tích sự cố tồn đọng
            total_tickets_count = $custTickets.Count
            open_tickets_count = $openTickets.Count
            critical_open_tickets_count = $criticalTickets.Count
            has_unresolved_incident = $hasUnresolvedIncident
            avg_csat = $avgCsat
            incident_detail = if ($hasUnresolvedIncident) { $criticalTickets[0].summary } else { "Không có sự cố tồn đọng" }

            # Đề xuất gói & kiểm tra chính sách
            current_package_id = $currentPkgId
            current_package_name = $c.current_package_name
            current_contract_value = $c.annual_contract_value
            proposed_package_id = $recommendedPkgId
            proposed_package_name = $targetPkg.package_name
            proposed_seats = $recommendedSeats
            recommendation_type = $recommendationType
            recommendation_rationale = $recommendationRationale
            applied_discount_pct = $validDiscountPct
            applied_promo_codes = ($appliedPromoCodes -join ", ")
            proposed_contract_value = $proposedContractValue
            revenue_delta = $revenueDelta

            # Cảnh báo vi phạm chính sách
            policy_violations = ($violations -join " | ")
            has_policy_violation = ($violations.Count -gt 0)

            # Bản nháp trao đổi
            draft_email_subject = $draftSubject
            draft_email_body = $draftBody

            # Quản lý luồng Bước 3 & Bước 4
            step3_status = $step3Status
            cs_review_notes = if ($hasUnresolvedIncident) { "CS đã ghi nhận sự cố, đang đôn đốc đội Kỹ thuật hoàn thành." } elseif ($activationPct -lt 50) { "CS đang lên lịch hẹn training tính năng với khách hàng." } else { "CS xác nhận khách hàng phản hồi tích cực." }
            sales_review_notes = if ($violations.Count -gt 0) { "Kinh doanh điều chỉnh lại chiết khấu theo chuẩn chính sách." } else { "Kinh doanh nhất trí phương án AI đề xuất." }
            approval_status = $managerDecision
            approval_notes = ""
            final_sent_date = $null
        }

        $masterDossiers += $dossier
    }

    # Xuất báo cáo tổng hợp
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    }

    $jsonOutput = Join-Path $OutputDir "renewal_master_report.json"
    $csvOutput = Join-Path $OutputDir "renewal_master_report.csv"

    $masterDossiers | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonOutput -Encoding UTF8
    $masterDossiers | Export-Csv -Path $csvOutput -NoTypeInformation -Encoding UTF8

    Write-Host "[HOÀN THÀNH BƯỚC 1 & BƯỚC 2] Đã xử lý toàn bộ $($masterDossiers.Count) hồ sơ gia hạn." -ForegroundColor Green
    
    # Báo cáo tóm tắt
    $overdueContact = @($masterDossiers | Where-Object { $_.days_to_contact_start -lt 0 }).Count
    $unresolvedIncident = @($masterDossiers | Where-Object { $_.has_unresolved_incident }).Count
    $policyViolations = @($masterDossiers | Where-Object { $_.has_policy_violation }).Count
    $lowAdoptions = @($masterDossiers | Where-Object { $_.activation_rate_pct -lt 50.0 }).Count
    $upsellCandidates = @($masterDossiers | Where-Object { $_.recommendation_type -in @("UPGRADE_PACKAGE", "ADD_SEATS") }).Count
    $readyToApprove = @($masterDossiers | Where-Object { $_.approval_status -eq "READY_FOR_APPROVAL" }).Count

    Write-Host "================== TÓM TẮT PHÂN TÍCH AI AGENT ==================" -ForegroundColor White
    Write-Host "  * Tổng số hợp đồng rà soát: $($masterDossiers.Count)" -ForegroundColor White
    Write-Host "  * Hồ sơ chậm tiến độ liên hệ (Cần xử lý ngay): $overdueContact" -ForegroundColor Red
    Write-Host "  * Hồ sơ có sự cố tồn đọng (ĐÃ TỰ ĐỘNG CHẶN UPSELL): $unresolvedIncident" -ForegroundColor Yellow
    Write-Host "  * Hồ sơ phát hiện vi phạm quy định ưu đãi: $policyViolations" -ForegroundColor Magenta
    Write-Host "  * Khách hàng dùng dưới 50% tài khoản (Nguy cơ Churn): $lowAdoptions" -ForegroundColor DarkYellow
    Write-Host "  * Hồ sơ có cơ hội Upsell / Nâng gói hợp lệ: $upsellCandidates" -ForegroundColor Cyan
    Write-Host "  * Hồ sơ đủ chuẩn sẵn sàng cho Trưởng phòng duyệt ngay: $readyToApprove" -ForegroundColor Green
    Write-Host "==================================================================" -ForegroundColor White

    return $masterDossiers
}

# Run when script is executed directly
Invoke-AnTinAIAgentPipeline

