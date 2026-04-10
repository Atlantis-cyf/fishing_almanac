function deepFreeze(value) {
  if (value && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const key of Object.keys(value)) {
      deepFreeze(value[key]);
    }
  }
  return value;
}

const CONTRACT_VERSION = '2026-04-mvp-v1';

const ANALYTICS_DASHBOARD_CONTRACT = {
  // phase-1 baseline version for define-kpi-contract
  contract_version: CONTRACT_VERSION,
  version: CONTRACT_VERSION,
  generated_from_plan: '海钓图鉴dashboard方案_e4b0e517.plan.md',
  contract_scope: ['overview', 'upload_funnel', 'ai_identify', 'collection_growth'],

  // 1.1 统一事件与字段清单
  event_catalog: {
    app_launch: ['event_type', 'occurred_at', 'user_id', 'anon_id', 'properties.platform'],
    home_view: ['event_type', 'occurred_at', 'user_id', 'anon_id', 'properties.platform'],
    upload_click: ['event_type', 'occurred_at', 'properties.entry_position', 'properties.platform'],
    upload_success: [
      'event_type',
      'occurred_at',
      'properties.entry_position',
      'properties.upload_duration_ms',
      'properties.platform',
    ],
    ai_identify_start: ['event_type', 'occurred_at', 'properties.request_id', 'properties.platform'],
    ai_identify_result: [
      'event_type',
      'occurred_at',
      'properties.request_id',
      'properties.species_name',
      'properties.latency_ms',
      'properties.platform',
    ],
    ai_identify_fail: [
      'event_type',
      'occurred_at',
      'properties.request_id',
      'properties.error_code',
      'properties.latency_ms',
      'properties.platform',
    ],
    species_unlock: ['event_type', 'occurred_at', 'user_id', 'anon_id', 'properties.species_name', 'properties.platform'],
    collection_view: [
      'event_type',
      'occurred_at',
      'user_id',
      'anon_id',
      'properties.unlocked_species_count',
      'properties.total_species_count',
      'properties.platform',
    ],
    species_detail_view: ['event_type', 'occurred_at', 'user_id', 'anon_id', 'properties.species_name', 'properties.platform'],
  },

  dimensions: {
    platform: { source: "properties.platform", type: 'string' },
    entry_position: { source: "properties.entry_position", type: 'string' },
    species_name: { source: "properties.species_name", type: 'string' },
    error_code: { source: "properties.error_code", type: 'string' },
    request_id: { source: "properties.request_id", type: 'string' },
  },

  // 1.2 冻结指标公式与分母规则
  metric_rules: {
    time_semantics: 'occurred_at',
    time_source: 'analytics_events.occurred_at',
    identity_key: "coalesce(user_id::text, anon_id)",
    uv_rule: 'count(distinct identity_key)',
    ai_request_dedup: "distinct properties->>'request_id'",
    conversion_denominator: 'same_time_window_previous_step_count',
    denominator_zero_behavior: {
      rate_metrics: 'return 0',
      uv_metrics: 'return 0',
    },
    time_window_alignment: 'numerator_and_denominator_must_share_same_filters_and_time_window',
  },

  // 1.3 冻结筛选器规范
  filter_schema: {
    parser_key: 'admin_analytics_filter_schema_v1',
    shared_filters: {
      time_range: {
        type: 'enum',
        options: ['today', '7d', '30d', 'custom'],
        default: '7d',
      },
      platform: {
        type: 'string',
        nullable: true,
        default: null,
      },
      entry_position: {
        type: 'string',
        nullable: true,
        default: null,
      },
    },
    custom_time_range: {
      required_when: "time_range='custom'",
      fields: ['from', 'to'],
      format: 'ISO-8601',
      timezone: 'UTC',
    },
  },
  time_range_options: ['today', '7d', '30d', 'custom'],

  // 1.1 + 1.2: 按 Dashboard 分组事件与指标依赖
  dashboards: {
    overview: {
      title: 'Overview',
      filters: ['time_range', 'platform'],
      kpis: {
        app_launch_count: {
          formula: 'count(app_launch)',
          events: ['app_launch'],
          fields: ['event_type', 'occurred_at'],
        },
        active_users_uv: {
          formula: "count(distinct coalesce(user_id::text, anon_id))",
          events: ['app_launch', 'home_view', 'upload_click', 'upload_success', 'collection_view'],
          fields: ['user_id', 'anon_id', 'occurred_at'],
        },
        upload_click_count: {
          formula: 'count(upload_click)',
          events: ['upload_click'],
          fields: ['event_type', 'occurred_at', 'properties.platform'],
        },
        upload_success_count: {
          formula: 'count(upload_success)',
          events: ['upload_success'],
          fields: ['event_type', 'occurred_at', 'properties.platform'],
        },
        ai_success_rate: {
          formula: 'count(ai_identify_result) / count(ai_identify_start)',
          events: ['ai_identify_result', 'ai_identify_start'],
          fields: ['event_type', 'occurred_at', 'properties.platform'],
        },
        collection_view_count: {
          formula: 'count(collection_view)',
          events: ['collection_view'],
          fields: ['event_type', 'occurred_at', 'properties.platform'],
        },
      },
      charts: {
        daily_trend: {
          events: ['app_launch', 'upload_success', 'collection_view'],
          fields: ['event_type', 'occurred_at', 'properties.platform'],
          metrics: ['app_launch_count', 'upload_success_count', 'collection_view_count'],
        },
        conversion_summary: {
          metrics: ['upload_conversion_rate', 'ai_success_rate'],
        },
      },
    },
    upload_funnel: {
      title: 'Upload Funnel',
      filters: ['time_range', 'platform', 'entry_position'],
      kpis: {
        upload_click_count: {
          formula: 'count(upload_click)',
          events: ['upload_click'],
          fields: ['event_type', 'occurred_at', 'properties.entry_position', 'properties.platform'],
        },
        upload_success_count: {
          formula: 'count(upload_success)',
          events: ['upload_success'],
          fields: ['event_type', 'occurred_at', 'properties.entry_position', 'properties.platform'],
        },
        upload_conversion_rate: {
          formula: 'count(upload_success) / count(upload_click)',
          events: ['upload_click', 'upload_success'],
          fields: ['event_type', 'occurred_at', 'properties.entry_position', 'properties.platform'],
        },
        upload_avg_duration_ms: {
          formula: 'avg(upload_duration_ms)',
          events: ['upload_success'],
          fields: ['properties.upload_duration_ms', 'occurred_at', 'properties.platform'],
        },
      },
      charts: {
        funnel_steps: {
          steps: ['upload_click', 'ai_identify_start', 'upload_success'],
          fields: ['event_type', 'occurred_at', 'properties.entry_position', 'properties.platform'],
        },
        entry_position_breakdown: {
          events: ['upload_click', 'upload_success'],
          fields: ['properties.entry_position', 'occurred_at', 'properties.platform'],
        },
        upload_duration_distribution: {
          events: ['upload_success'],
          fields: ['properties.upload_duration_ms', 'occurred_at', 'properties.platform'],
          aggregates: ['p50', 'p95', 'avg'],
        },
      },
    },
    ai_identify: {
      title: 'AI Identify',
      filters: ['time_range', 'platform'],
      kpis: {
        identify_start_count: {
          formula: 'count(ai_identify_start)',
          events: ['ai_identify_start'],
          fields: ['event_type', 'occurred_at', 'properties.platform'],
        },
        identify_success_rate: {
          formula: 'count(ai_identify_result) / count(ai_identify_start)',
          events: ['ai_identify_result', 'ai_identify_start'],
          fields: ['event_type', 'occurred_at', 'properties.platform'],
        },
        identify_fail_rate: {
          formula: 'count(ai_identify_fail) / count(ai_identify_start)',
          events: ['ai_identify_fail', 'ai_identify_start'],
          fields: ['event_type', 'occurred_at', 'properties.platform'],
        },
        identify_latency_p50_ms: {
          formula: 'p50(latency_ms)',
          events: ['ai_identify_result', 'ai_identify_fail'],
          fields: ['properties.latency_ms', 'occurred_at', 'properties.platform'],
        },
        identify_latency_p95_ms: {
          formula: 'p95(latency_ms)',
          events: ['ai_identify_result', 'ai_identify_fail'],
          fields: ['properties.latency_ms', 'occurred_at', 'properties.platform'],
        },
      },
      charts: {
        latency_daily_trend: {
          events: ['ai_identify_result', 'ai_identify_fail'],
          fields: ['properties.latency_ms', 'occurred_at', 'properties.platform'],
          aggregates: ['p50', 'p95'],
        },
        top_species: {
          events: ['ai_identify_result'],
          fields: ['properties.species_name', 'occurred_at', 'properties.platform'],
        },
        fail_reason_distribution: {
          events: ['ai_identify_fail'],
          fields: ['properties.error_code', 'occurred_at', 'properties.platform'],
        },
      },
    },
    collection_growth: {
      title: 'Collection Growth',
      filters: ['time_range', 'platform'],
      kpis: {
        species_unlock_count: {
          formula: 'count(species_unlock)',
          events: ['species_unlock'],
          fields: ['event_type', 'occurred_at', 'properties.species_name', 'properties.platform'],
        },
        collection_view_uv: {
          formula: "count(distinct identity_key where event_type='collection_view')",
          events: ['collection_view'],
          fields: ['user_id', 'anon_id', 'occurred_at', 'properties.platform'],
        },
        species_detail_view_uv: {
          formula: "count(distinct identity_key where event_type='species_detail_view')",
          events: ['species_detail_view'],
          fields: ['user_id', 'anon_id', 'occurred_at', 'properties.platform'],
        },
        unlock_to_detail_conversion_rate: {
          formula: 'distinct_identity(species_detail_view after unlock) / distinct_identity(species_unlock)',
          events: ['species_unlock', 'species_detail_view'],
          fields: ['user_id', 'anon_id', 'occurred_at', 'properties.platform'],
        },
      },
      charts: {
        unlock_daily_trend: {
          events: ['species_unlock'],
          fields: ['occurred_at', 'properties.platform'],
        },
        unlock_top_species: {
          events: ['species_unlock'],
          fields: ['properties.species_name', 'occurred_at', 'properties.platform'],
        },
        post_unlock_behavior: {
          description: 'Whether species_detail_view happens within 24h after species_unlock',
          events: ['species_unlock', 'species_detail_view'],
          fields: ['user_id', 'anon_id', 'occurred_at', 'properties.platform'],
          attribution_window: '24h',
        },
      },
    },
  },
  event_field_dependencies: {
    upload_funnel: {
      events: ['upload_click', 'ai_identify_start', 'upload_success'],
      required_fields: ['event_type', 'occurred_at', 'properties.entry_position', 'properties.platform'],
    },
    ai_latency_trend: {
      events: ['ai_identify_result', 'ai_identify_fail'],
      required_fields: [
        'event_type',
        'occurred_at',
        'properties.latency_ms',
        'properties.error_code',
        'properties.species_name',
        'properties.platform',
      ],
    },
    collection_growth_trend: {
      events: ['species_unlock', 'collection_view', 'species_detail_view'],
      required_fields: [
        'event_type',
        'occurred_at',
        'properties.species_name',
        'properties.unlocked_species_count',
        'properties.total_species_count',
        'properties.platform',
      ],
    },
    overview_trend: {
      events: ['app_launch', 'upload_success', 'collection_view'],
      required_fields: ['event_type', 'occurred_at', 'user_id', 'anon_id', 'properties.platform'],
    },
  },
  // 1.4 定义异常/空值策略：将查询层容错行为集中配置，避免不同接口处理不一致。
  data_quality_rules: {
    // properties 缺字段时按 null 处理，查询中必须使用安全提取。
    missing_properties_field: {
      behavior: 'treat_as_null',
      query_guard: 'safe_json_extract_with_default',
    },
    // 类型异常时优先安全转换，失败回落 null，防止聚合阶段抛错。
    type_mismatch: {
      behavior: 'coerce_if_safe_else_null',
      examples: ['latency_ms', 'upload_duration_ms', 'unlocked_species_count'],
    },
    // 比率类指标在分母为 0 时固定返回 0，避免 NaN/Infinity 进入接口响应。
    zero_denominator: {
      behavior: 'return_0',
      applies_to: ['upload_conversion_rate', 'identify_success_rate', 'identify_fail_rate', 'ai_success_rate'],
    },
    // AI 识别链路优先按 request_id 去重，缺失时才回落到事件级统计。
    request_id_dedup: {
      behavior: 'dedup_by_request_id_first',
      fallback: 'event_row_level_when_request_id_missing',
    },
    // 平台字段为空时归档到 unknown 桶，避免 group by 丢失记录。
    null_platform: {
      behavior: 'bucket_to_unknown',
      bucket_value: '__unknown__',
    },
  },
  // 1.5 合同评审与版本冻结：后续改动必须附带版本与评审信息。
  changelog_template: {
    required_fields: ['contract_version', 'change_summary', 'owner', 'reviewers', 'compatible_since', 'breaking_change'],
    sample: {
      contract_version: '2026-04-mvp-v2',
      change_summary: 'add identify_timeout_rate in ai_identify dashboard',
      owner: 'analytics-backend',
      reviewers: ['admin-frontend', 'data'],
      compatible_since: '2026-04-mvp-v1',
      breaking_change: false,
    },
  },
  notes: [
    'When ENABLE_ANALYTICS=false, the dashboard data can be empty.',
    'Use coalesce(user_id, anon_id) for UV metrics.',
    'occurred_at is server ingest time; delayed client retries can shift data.',
    "For AI dedup, prioritize properties.request_id when available.",
    'properties is jsonb with weak schema; always guard null/type conversion in query.',
  ],
};

module.exports = {
  CONTRACT_VERSION,
  ANALYTICS_DASHBOARD_CONTRACT: deepFreeze(ANALYTICS_DASHBOARD_CONTRACT),
};
