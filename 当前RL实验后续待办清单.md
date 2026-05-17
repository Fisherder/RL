# 当前 RL 实验后续待办清单

本文档基于当前 `RL/` 最新仓库状态整理。最新代码已经新增一套更偏“可复现与稳定运行”的 Stage2 入口，包括 `main_grpo_pentest_r1_stage2_repro.sh`、`launch_pentest_r1_stage2_repro.sh`、`run_pentest_r1_full_repro.sh`、`quality_speed` 快速路径、Verl 多轮 patch 脚本、baseline/quality-speed interaction 配置和 rollout early-stop 工具。

当前后续工作应分成两条线推进：

- **复现线**：先跑通严格 no-judge baseline，作为 Pentest-R1 Stage2 对齐基线。
- **方法线**：在复现线稳定后，新增或恢复严格 judge 入口，用同口径跑 Judge progress reward 方法，并做统一 AutoPenBench 评测。

## 0. 当前最新仓库状态

| 项目 | 当前状态 | 后续动作 |
|---|---|---|
| Stage1 模型 | 脚本默认读取 `../Pentest-R1/outputs/grpo_stage1/merged_model`；当前本地快照未包含权重目录 | 在训练服务器确认该路径存在；不存在则先跑 Stage1 或拷贝 merged model |
| Stage2 数据 | 本地已有 `pentest-r1-stage2` 和 `pentest-r1-stage2-offline` parquet | baseline 复现需要生成或确认 `pentest-r1-stage2-repro`；quality-speed 需要生成 `pentest-r1-stage2-quality-speed` |
| Repro baseline 入口 | 新增 `purpcode/rl/main_grpo_pentest_r1_stage2_repro.sh` | 作为严格 no-judge baseline 主入口 |
| 后台启动入口 | 新增 `purpcode/script/launch_pentest_r1_stage2_repro.sh` | 长时间训练建议用它启动并保留 pid/nohup/run_logs |
| 全链路入口 | 新增 `purpcode/script/run_pentest_r1_full_repro.sh` | 用于从 Stage1 到 Stage2 全量复现；成本更高，非第一优先级 |
| Quality-speed 入口 | 新增 `purpcode/rl/main_grpo_pentest_r1_stage2_quality_speed.sh` | 只作为 smoke/工程加速，不作为正式论文主结果 |
| Verl patch | 新增 `purpcode/script/patch_verl_pentest_multiturn.py` | repro 脚本会自动 apply；训练前仍需留意 patch 是否成功 |
| Baseline interaction | 新增 `purpcode/rl/pentest_r1_stage2_interaction_baseline.yaml` | baseline 使用，`judge_progress.enabled=false` |
| Quality-speed interaction | 新增 `purpcode/rl/pentest_r1_stage2_interaction_quality_speed.yaml` | 快速验证使用，`max_steps=2`、不要求 `</think>` |
| Judge 入口 | 最新 `repro.sh` 顶部强制 `PENTEST_R1_STAGE2_ENABLE_JUDGE_PROGRESS=0`，且默认 baseline config | 正式 Judge 实验前必须新增 judge repro wrapper 或改成可配置 judge 开关 |
| AutoPenBench 评测 | 仍使用 `script/run_autopenbench_full.sh` | 注意显式覆盖 `AUTOPENBENCH_MODEL_PATH`，否则会评测旧默认路径 |

## 1. 总原则

| 原则 | 说明 |
|---|---|
| 主实验优先使用 repro 入口 | 最新仓库的稳定性、日志、资源检查、Ray 日志抓取都集中在 `main_grpo_pentest_r1_stage2_repro.sh` |
| no-judge baseline 先跑通 | 最新 repro 入口明确是 baseline/no-judge，先拿到可信 baseline 再做 Judge 方法 |
| quality-speed 不能作为论文主结果 | 它默认 `max_steps=2`、`turn_max_new_tokens=128`、`max_interaction_tokens=512`，与正式 8 步设置不同 |
| Judge 是唯一方法变量 | Judge 方法应尽量复用 repro 入口的日志、patch、preflight、batch 和训练参数，只更换 interaction config 与 judge 开关 |
| AutoPenBench 预算必须统一 | 正式评测使用 33 tasks、30 epochs、`temperature=0.0`、`prompt_style=action`、`observation_mode=raw` |
| 结果必须可追溯 | 每次训练必须保留 `run_logs/<timestamp>/env.txt`、`command.txt`、`train.log`、`exit_status.txt` 和 checkpoint |

## 2. Phase 0：同步后必须先做的检查

默认训练服务器路径：

```bash
cd /home/ubuntu/RL/purpcode
```

### 2.1 检查 Stage1 merged model

```bash
ls /home/ubuntu/RL/Pentest-R1/outputs/grpo_stage1/merged_model/config.json
ls /home/ubuntu/RL/Pentest-R1/outputs/grpo_stage1/merged_model/tokenizer_config.json
```

如果不存在：

| 情况 | 处理 |
|---|---|
| 其他机器已有 merged model | 拷贝到 `/home/ubuntu/RL/Pentest-R1/outputs/grpo_stage1/merged_model` |
| 只有中间 checkpoint | 先运行 merge，生成 HuggingFace 目录 |
| 完全没有 Stage1 | 先跑 `Pentest-R1/grpo_stage1.py` 或使用 `script/run_pentest_r1_full_repro.sh` 全链路复现 |

### 2.2 检查数据集

已有数据：

```bash
ls local_data/pentest-r1-stage2/train.parquet
ls local_data/pentest-r1-stage2/test.parquet
ls local_data/pentest-r1-stage2-offline/train.parquet
ls local_data/pentest-r1-stage2-offline/test.parquet
```

生成 repro 数据：

```bash
conda run --no-capture-output -n purpcode python rl/data/pentest_r1_stage2.py \
  --root-dir ./local_data \
  --dataset-name pentest-r1-stage2-repro
```

生成 quality-speed 数据：

```bash
bash script/build_pentest_r1_stage2_quality_speed_dataset.sh
```

完成标准：

| 数据集 | 用途 | 是否主结果 |
|---|---|---|
| `pentest-r1-stage2` | 旧 strict 主实验数据 | 可作为对照 |
| `pentest-r1-stage2-repro` | 最新 repro baseline 默认数据 | 是，优先 |
| `pentest-r1-stage2-quality-speed` | 快速 smoke / 工程加速 | 否 |
| `pentest-r1-stage2-offline` | 旧 offline 子集 | 否，只能做工程记录 |

### 2.3 检查 Docker 与 AutoPenBench 资产

```bash
docker image inspect intercode-ctf
ls /home/ubuntu/RL/auto-pen-bench-official/data/games.json
ls /home/ubuntu/RL/auto-pen-bench-official/benchmark/machines/docker-compose.yml
```

AutoPenBench 资产检查：

```bash
conda run --no-capture-output -n purpcode python script/eval_autopenbench.py \
  --autopenbench-root /home/ubuntu/RL/auto-pen-bench-official \
  --check-assets
```

### 2.4 检查磁盘和 GPU

最新 repro 脚本默认要求输出目录和 Ray 临时目录至少有 150GB 可用空间：

```bash
df -h / /tmp /home/ubuntu/RL /mnt/sda
nvidia-smi
```

如果磁盘不足：

| 选择 | 命令或处理 |
|---|---|
| 清理旧 Ray/session/logs/checkpoints | 手动清理确认无用目录 |
| 换输出目录 | 设置 `PENTEST_R1_REPRO_STAGE2_OUTPUT_DIR=/mnt/sda/...` |
| 降低 preflight 阈值 | 仅在确认空间够用时设置 `PENTEST_R1_REPRO_STAGE2_MIN_FREE_GB=<更小值>` |

## 3. Phase 1：代码级测试与 wiring 检查

最新仓库新增了 rollout utils 测试，也要一起跑。

```bash
cd /home/ubuntu/RL/purpcode

conda run --no-capture-output -n purpcode python -m unittest \
  test/test_pentest_r1_stage2.py \
  test/test_pentest_r1_stage2_judge.py \
  test/test_pentest_r1_stage2_rollout_utils.py
```

再跑 wiring / judge integration：

```bash
conda run --no-capture-output -n purpcode python script/check_pentest_r1_stage2_wiring.py
conda run --no-capture-output -n purpcode python script/test_pentest_r1_stage2_judge_integration.py
```

完成标准：

| 检查项 | 通过条件 |
|---|---|
| Stage2 单元测试 | prompt、Action 解析、dataset example 正常 |
| Judge 单元测试 | delta、cap、anti-repeat、fallback 正常 |
| Rollout utils 测试 | early stop、heredoc、submit、response window 正常 |
| Wiring check | fake episode 能产生 base reward 与 judge reward |

## 4. Phase 2：先跑 quality-speed smoke

目的：快速验证最新 patch、rollout early-stop、日志目录、资源监控和容器清理是否正常。该结果不进入论文主表。

```bash
cd /home/ubuntu/RL/purpcode

CUDA_VISIBLE_DEVICES=0,1,2,3 \
PENTEST_R1_REPRO_STAGE2_MAX_EPOCHS=1 \
PENTEST_R1_REPRO_STAGE2_SAVE_FREQ=1 \
bash rl/main_grpo_pentest_r1_stage2_quality_speed.sh
```

完成标准：

| 产物 | 路径或判断 |
|---|---|
| checkpoint | `models/pentest-r1-stage2-quality-speed-*/global_step_*` |
| 训练日志 | `models/<experiment>/run_logs/<timestamp>/train.log` |
| 环境记录 | `env.txt`、`command.txt`、`exit_status.txt` |
| Ray 日志快照 | `run_logs/<timestamp>/ray_logs/`，如 Ray 目录存在 |
| 资源监控 | `resource_monitor.log`，如果启用 |

如果 quality-speed 都不能稳定跑通，不要直接跑正式 baseline，先解决工程问题。

## 5. Phase 3：正式 no-judge baseline 复现

最新 baseline 主入口：

```bash
cd /home/ubuntu/RL/purpcode

CUDA_VISIBLE_DEVICES=0,1,2,3 \
PENTEST_R1_REPRO_STAGE2_DATASET=pentest-r1-stage2-repro \
PENTEST_R1_REPRO_STAGE2_EXPERIMENT_NAME=pentest-r1-stage2-repro-nojudge-$(date +%Y%m%d_%H%M%S) \
bash rl/main_grpo_pentest_r1_stage2_repro.sh
```

长时间后台运行建议使用：

```bash
cd /home/ubuntu/RL/purpcode

CUDA_VISIBLE_DEVICES=0,1,2,3 \
PENTEST_R1_REPRO_STAGE2_DATASET=pentest-r1-stage2-repro \
bash script/launch_pentest_r1_stage2_repro.sh
```

完成标准：

| 产物 | 路径 |
|---|---|
| checkpoint | `purpcode/models/<experiment>/global_step_<N>/actor/huggingface/` |
| train log | `purpcode/models/<experiment>/run_logs/<timestamp>/train.log` |
| exit status | `purpcode/models/<experiment>/run_logs/<timestamp>/exit_status.txt` |
| command log | `purpcode/models/<experiment>/run_logs/<timestamp>/command.txt` |
| env log | `purpcode/models/<experiment>/run_logs/<timestamp>/env.txt` |

记录字段：

```text
experiment_name=<实际实验名>
dataset=pentest-r1-stage2-repro
judge_enabled=false
interaction_config=rl/pentest_r1_stage2_interaction_baseline.yaml
max_epochs=2
max_steps=8
max_prompt_len=1536
max_response_len=512
turn_max_new_tokens=2048
max_context_length=4096
max_interaction_tokens=16384
train_batch_size=4
rollout_n=2
checkpoint=global_step_<N>
```

## 6. Phase 4：恢复或新增 strict judge repro 入口

最新 `main_grpo_pentest_r1_stage2_repro.sh` 顶部有：

```bash
export PENTEST_R1_STAGE2_ENABLE_JUDGE_PROGRESS=0
```

并且默认使用：

```bash
INTERACTION_CONFIG=./rl/pentest_r1_stage2_interaction_baseline.yaml
```

因此，正式 Judge 实验前必须做一个明确改动。建议新增文件，不直接破坏 baseline：

```text
purpcode/rl/main_grpo_pentest_r1_stage2_repro_judge.sh
purpcode/rl/pentest_r1_stage2_interaction_judge.yaml
```

### 6.1 建议的 judge interaction 配置

以 `pentest_r1_stage2_interaction_baseline.yaml` 为基础，保留 baseline 的关键格式设置，但开启 Judge：

```yaml
interactions:
  pentest_r1_ctf:
    class_name: rl.pentest_r1_stage2.interaction.PentestR1Stage2Interaction
    config:
      image_name: intercode-ctf
      traj_dir: logs/ctf/
      verbose: true
      max_steps: 8
      max_observation_chars: 1600
      require_think_end: true
      judge_progress:
        enabled: true
        evaluate_every_n_steps: 2
        recent_window_size: 2
        judge_delta_clip: 0.15
        judge_total_bonus_cap: 0.4
        judge_total_penalty_cap: 0.25
        repetitive_penalty: 0.02
        stalling_penalty: 0.03
        hallucinated_progress_penalty: 0.06
        assistant_max_chars: 1200
        observation_max_chars: 1000
        summary_max_items: 6
        evidence_max_items: 12
        logger_dir: logs/judge_progress
        base_url: https://dashscope.aliyuncs.com/compatible-mode/v1
        model: qwen3.5-27b
        api_key_env: DASHSCOPE_API_KEY
        timeout_seconds: 30.0
        max_retries: 3
        retry_wait_seconds: 2.0
```

### 6.2 建议的 judge wrapper 行为

`main_grpo_pentest_r1_stage2_repro_judge.sh` 应复用 repro 脚本的所有 preflight、patch、日志、资源监控，只覆盖：

```bash
export PENTEST_R1_STAGE2_ENABLE_JUDGE_PROGRESS=1
export PENTEST_R1_REPRO_STAGE2_INTERACTION_CONFIG=./rl/pentest_r1_stage2_interaction_judge.yaml
export PENTEST_R1_REPRO_STAGE2_EXPERIMENT_NAME=${PENTEST_R1_REPRO_STAGE2_EXPERIMENT_NAME:-pentest-r1-stage2-repro-judge-$(date +%Y%m%d_%H%M%S)}
export PENTEST_R1_REPRO_STAGE2_OUTPUT_DIR=${PENTEST_R1_REPRO_STAGE2_OUTPUT_DIR:-./models/$PENTEST_R1_REPRO_STAGE2_EXPERIMENT_NAME}
exec bash rl/main_grpo_pentest_r1_stage2_repro.sh "$@"
```

但注意：如果 `repro.sh` 内部仍强制 `export PENTEST_R1_STAGE2_ENABLE_JUDGE_PROGRESS=0`，wrapper 设置会被覆盖。需要把 `repro.sh` 改为：

```bash
export PENTEST_R1_STAGE2_ENABLE_JUDGE_PROGRESS=${PENTEST_R1_STAGE2_ENABLE_JUDGE_PROGRESS:-0}
```

完成标准：

| 检查项 | 通过条件 |
|---|---|
| baseline 默认不变 | 直接跑 `repro.sh` 仍为 no-judge |
| judge wrapper 生效 | 跑 `repro_judge.sh` 时 `judge_progress.enabled=true` |
| 日志一致 | judge 和 no-judge 都保留 run_logs |
| 变量唯一 | 两组除 Judge config / enable 外，其他训练参数一致 |

## 7. Phase 5：正式 strict judge 训练

确认 `DASHSCOPE_API_KEY`：

```bash
echo "$DASHSCOPE_API_KEY"
```

启动：

```bash
cd /home/ubuntu/RL/purpcode

CUDA_VISIBLE_DEVICES=0,1,2,3 \
PENTEST_R1_REPRO_STAGE2_DATASET=pentest-r1-stage2-repro \
PENTEST_R1_REPRO_STAGE2_EXPERIMENT_NAME=pentest-r1-stage2-repro-judge-$(date +%Y%m%d_%H%M%S) \
bash rl/main_grpo_pentest_r1_stage2_repro_judge.sh
```

完成标准：

| 产物 | 路径 |
|---|---|
| checkpoint | `purpcode/models/<judge_experiment>/global_step_<N>/actor/huggingface/` |
| judge logs | `purpcode/logs/judge_progress/*.jsonl` 或配置指定目录 |
| run logs | `purpcode/models/<judge_experiment>/run_logs/<timestamp>/` |
| exit status | `EXIT_CODE=0` |

必须检查：

| 检查项 | 要求 |
|---|---|
| judge 调用次数 | 不为 0 |
| fallback rate | 不能过高，否则这次训练不能作为正式 Judge 结果 |
| final_reward | 不能全部为 0，也不能大量撞 cap |
| duplicate_blocked | 有无触发都要统计，用于分析 anti-repeat |

## 8. Phase 6：统一 AutoPenBench 评测

正式评测参数固定：

```text
AUTOPENBENCH_EPOCHS_DEFAULT=30
AUTOPENBENCH_MAX_INPUT_TOKENS=4096
AUTOPENBENCH_MAX_NEW_TOKENS=1536
AUTOPENBENCH_SUMMARY_MAX_NEW_TOKENS=192
AUTOPENBENCH_TEMPERATURE=0.0
prompt_style=action
observation_mode=raw
```

### 8.1 评测 no-judge baseline

```bash
cd /home/ubuntu/RL/purpcode

AUTOPENBENCH_MODEL_PATH=/home/ubuntu/RL/purpcode/models/<nojudge_experiment>/global_step_<N>/actor/huggingface \
AUTOPENBENCH_ROOT=/home/ubuntu/RL/auto-pen-bench-official \
AUTOPENBENCH_OUTPUT_ROOT=/home/ubuntu/RL/purpcode/eval_results/autopenbench_repro_nojudge_step<N> \
AUTOPENBENCH_EPOCHS_DEFAULT=30 \
AUTOPENBENCH_MAX_INPUT_TOKENS=4096 \
AUTOPENBENCH_MAX_NEW_TOKENS=1536 \
AUTOPENBENCH_SUMMARY_MAX_NEW_TOKENS=192 \
AUTOPENBENCH_TEMPERATURE=0.0 \
bash script/run_autopenbench_full.sh
```

### 8.2 评测 judge

```bash
cd /home/ubuntu/RL/purpcode

AUTOPENBENCH_MODEL_PATH=/home/ubuntu/RL/purpcode/models/<judge_experiment>/global_step_<N>/actor/huggingface \
AUTOPENBENCH_ROOT=/home/ubuntu/RL/auto-pen-bench-official \
AUTOPENBENCH_OUTPUT_ROOT=/home/ubuntu/RL/purpcode/eval_results/autopenbench_repro_judge_step<N> \
AUTOPENBENCH_EPOCHS_DEFAULT=30 \
AUTOPENBENCH_MAX_INPUT_TOKENS=4096 \
AUTOPENBENCH_MAX_NEW_TOKENS=1536 \
AUTOPENBENCH_SUMMARY_MAX_NEW_TOKENS=192 \
AUTOPENBENCH_TEMPERATURE=0.0 \
bash script/run_autopenbench_full.sh
```

### 8.3 评测完整性检查

```bash
cat eval_results/autopenbench_repro_nojudge_step<N>/aggregate_summary.json
cat eval_results/autopenbench_repro_judge_step<N>/aggregate_summary.json
find eval_results/autopenbench_repro_nojudge_step<N> -name exit_code.txt -print -exec cat {} \;
find eval_results/autopenbench_repro_judge_step<N> -name exit_code.txt -print -exec cat {} \;
```

完成标准：

| 字段 | 要求 |
|---|---|
| `num_scenarios` | 5 |
| `num_failed_runs` | 0 |
| `num_tasks` | 33 |
| `num_success` | 记录成功数 |
| `success_rate` | 记录成功率 |

## 9. Phase 7：结果登记与对比

新增结果登记文件：

```text
purpcode/eval_results/EXPERIMENT_REGISTRY.md
```

建议格式：

```markdown
| Date | Model | Script | Dataset | Judge | Checkpoint | APB Output Dir | Failed Runs | Success / Tasks | SR |
|---|---|---|---|---|---|---|---:|---:|---:|
| 2026-xx-xx | Repro no-judge | main_grpo_pentest_r1_stage2_repro.sh | pentest-r1-stage2-repro | no | global_step_<N> | autopenbench_repro_nojudge_step<N> | 0 | TBD / 33 | TBD |
| 2026-xx-xx | Repro judge | main_grpo_pentest_r1_stage2_repro_judge.sh | pentest-r1-stage2-repro | yes | global_step_<N> | autopenbench_repro_judge_step<N> | 0 | TBD / 33 | TBD |
| 2026-xx-xx | Quality-speed smoke | main_grpo_pentest_r1_stage2_quality_speed.sh | pentest-r1-stage2-quality-speed | no | global_step_<N> | none | n/a | n/a | n/a |
```

## 10. Phase 8：补充两个分析脚本

### 10.1 Judge 日志分析脚本

建议新增：

```text
purpcode/script/analyze_judge_progress_logs.py
```

输出：

| 指标 | 用途 |
|---|---|
| judge 调用次数 | 确认 Judge 实际启用 |
| fallback 次数和比例 | 判断 API 是否稳定 |
| 平均 raw_delta | 判断是否有有效进展分 |
| 平均 final_reward | 判断 shaping 强度 |
| positive / negative / zero reward 占比 | 分析 reward 分布 |
| cap_adjustment 次数 | 判断是否频繁撞 cap |
| duplicate_blocked 次数 | 验证 anti-repeat 是否起作用 |
| repetitive / stalling / hallucinated flags | 分析负向标记 |
| stage 分布 | 看模型主要卡在哪些阶段 |

建议输出：

```text
purpcode/logs/judge_progress_summary.json
purpcode/logs/judge_progress_summary.md
```

### 10.2 AutoPenBench 逐任务对比脚本

建议新增：

```text
purpcode/script/compare_autopenbench_runs.py
```

输入：

```bash
python script/compare_autopenbench_runs.py \
  --baseline-root eval_results/autopenbench_repro_nojudge_step<N> \
  --judge-root eval_results/autopenbench_repro_judge_step<N> \
  --output eval_results/compare_repro_nojudge_vs_judge_step<N>.md
```

输出字段：

| 字段 | 说明 |
|---|---|
| scenario | 五类场景之一 |
| task / case id | 任务标识 |
| no-judge success | baseline 是否成功 |
| judge success | Judge 是否成功 |
| delta | `win/loss/tie_fail/tie_success` |
| no-judge final action | baseline 最终动作 |
| judge final action | Judge 最终动作 |

## 11. 后续消融优先级

主实验完成后再做消融，不要在 baseline 和 judge 主结果之前分散精力。

| 优先级 | 消融 | 实现方式 | 目的 |
|---|---|---|---|
| P0 | no-judge repro | 最新 `main_grpo_pentest_r1_stage2_repro.sh` | 主 baseline |
| P0 | judge repro | 新增 `main_grpo_pentest_r1_stage2_repro_judge.sh` | 主方法 |
| P1 | quality-speed | `main_grpo_pentest_r1_stage2_quality_speed.sh` | 工程速度探索，不进主表 |
| P1 | no negative flags | 将 `repetitive/stalling/hallucinated` penalty 设为 0 | 验证负向 Judge 标记作用 |
| P1 | no cap | 提高或关闭 `judge_total_bonus_cap` | 验证 cap 防止 reward overpower |
| P1 | different frequency | `evaluate_every_n_steps=1/4` | 评估成本与效果折中 |
| P2 | heuristic progress reward | 用规则奖励新文件、新 URL、新 artifact | 对比 LLM Judge 与规则 shaping |
| P2 | random judge | 随机或打乱 judge score | 排除“多一个 reward”本身的解释 |

## 12. 目前最应该立刻做的 12 件事

| 顺序 | 任务 | 完成标志 |
|---:|---|---|
| 1 | 在训练服务器确认 Stage1 merged model 存在 | `config.json`、tokenizer 文件可见 |
| 2 | 生成 `pentest-r1-stage2-repro` 数据集 | `local_data/pentest-r1-stage2-repro/train.parquet` 存在 |
| 3 | 生成 `pentest-r1-stage2-quality-speed` 数据集 | `local_data/pentest-r1-stage2-quality-speed/train.parquet` 存在 |
| 4 | 跑三个 unittest | Stage2、Judge、rollout utils 全通过 |
| 5 | 跑 wiring / judge integration check | fake episode 正常 |
| 6 | 跑 quality-speed smoke | 能生成 checkpoint 和 run_logs |
| 7 | 跑 repro no-judge 正式训练 | `global_step_<N>/actor/huggingface` 存在 |
| 8 | 新增 judge repro wrapper 和 judge yaml | baseline 不变，judge wrapper 可启用 Judge |
| 9 | 跑 repro judge 正式训练 | checkpoint 和 judge logs 存在 |
| 10 | 用 30 epochs 评测 no-judge | `num_failed_runs=0` |
| 11 | 用 30 epochs 评测 judge | `num_failed_runs=0` |
| 12 | 做逐任务对比和 Judge 日志分析 | 生成 compare md 和 judge summary |

## 13. 常见坑位

| 坑位 | 后果 | 规避 |
|---|---|---|
| 继续只用旧 `main_grpo_pentest_r1_stage2.sh` | 错过最新 repro 日志、patch、preflight 和稳定性改动 | baseline 主线改用 `main_grpo_pentest_r1_stage2_repro.sh` |
| 误把 quality-speed 当主结果 | `max_steps=2` 等设置与正式实验不一致 | 只作为 smoke 或工程探索 |
| wrapper 设置 Judge 但被 repro 脚本覆盖为 0 | 实际仍是 no-judge | 修改 repro 脚本，使 enable 变量可配置 |
| 忘记生成 `pentest-r1-stage2-repro` | repro 脚本找不到默认数据 | 先运行数据生成命令 |
| 忘记覆盖 `AUTOPENBENCH_MODEL_PATH` | 评测旧默认 checkpoint | 每次评测前显式设置并登记 |
| scenario `exit_code=1` | aggregate 结果不完整 | 必须检查所有 `exit_code.txt` |
| Judge API key 为空 | Judge fallback，方法无效 | 训练前确认 `DASHSCOPE_API_KEY` |
| 磁盘不足 | repro preflight 直接失败 | 提前检查 150GB 空间或改输出目录 |
| GPU 被旧进程占用 | GPU preflight 失败或训练不稳定 | 用 `nvidia-smi` 清理旧 Ray/vLLM/训练进程 |

## 14. 最终交付物

当前阶段结束时，至少应形成：

```text
purpcode/models/<nojudge_experiment>/global_step_<N>/actor/huggingface/
purpcode/models/<judge_experiment>/global_step_<N>/actor/huggingface/
purpcode/models/<nojudge_experiment>/run_logs/<timestamp>/
purpcode/models/<judge_experiment>/run_logs/<timestamp>/
purpcode/eval_results/autopenbench_repro_nojudge_step<N>/aggregate_summary.json
purpcode/eval_results/autopenbench_repro_judge_step<N>/aggregate_summary.json
purpcode/eval_results/EXPERIMENT_REGISTRY.md
purpcode/eval_results/compare_repro_nojudge_vs_judge_step<N>.md
purpcode/logs/judge_progress_summary.json
purpcode/logs/judge_progress_summary.md
```

这些产物齐全后，论文中的“严格 no-judge 消融”和“Judge 进展奖励方法”才有可追溯、可复核的实验支撑。
