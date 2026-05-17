# 当前 RL 实验后续待办清单

本文档基于当前 `RL/` 最新仓库状态整理。最新代码已经新增一套更偏“可复现与稳定运行”的 Stage2 入口，包括 `main_grpo_pentest_r1_stage2_repro.sh`、`launch_pentest_r1_stage2_repro.sh`、`run_pentest_r1_full_repro.sh`、`quality_speed` 快速路径、Verl 多轮 patch 脚本、baseline/quality-speed interaction 配置和 rollout early-stop 工具。

当前阶段的核心目标不是先追求论文正式结果，而是先把训练链路完整跑起来。也就是说，当前优先级应调整为：

- **P0 跑通线**：优先使用 `main_grpo_pentest_r1_stage2_quality_speed.sh`，以最低可接受成本跑完一次 Stage2 训练，拿到 `EXIT_CODE=0`、checkpoint、完整 `run_logs` 和可复查的训练日志。
- **P1 稳定线**：在 quality-speed 至少成功一次后，复跑一次并记录耗时、显存、磁盘、失败点和关键参数，确认问题不是偶然规避。
- **P2 正式线**：在训练链路稳定后，再切换到 strict no-judge repro 与 strict judge repro，作为论文正式消融与方法结果。

因此，本文档中所有“正式 no-judge baseline”“Judge 方法训练”“AutoPenBench 统一评测”均为后续目标；当前最优先目标是让 speed 版本先成功跑完训练。

## 0. 当前最新仓库状态

| 项目 | 当前状态 | 后续动作 |
|---|---|---|
| Stage1 模型 | 脚本默认读取 `../Pentest-R1/outputs/grpo_stage1/merged_model`；当前本地快照未包含权重目录 | 在训练服务器确认该路径存在；不存在则先跑 Stage1 或拷贝 merged model |
| Stage2 数据 | 本地已有 `pentest-r1-stage2` 和 `pentest-r1-stage2-offline` parquet | 当前先生成 `pentest-r1-stage2-quality-speed`；`pentest-r1-stage2-repro` 可后置 |
| Repro baseline 入口 | 新增 `purpcode/rl/main_grpo_pentest_r1_stage2_repro.sh` | 后续正式 strict no-judge baseline 主入口，不是当前第一优先级 |
| 后台启动入口 | 新增 `purpcode/script/launch_pentest_r1_stage2_repro.sh` | 长时间训练建议用它启动并保留 pid/nohup/run_logs |
| 全链路入口 | 新增 `purpcode/script/run_pentest_r1_full_repro.sh` | 用于从 Stage1 到 Stage2 全量复现；成本更高，非第一优先级 |
| Quality-speed 入口 | 新增 `purpcode/rl/main_grpo_pentest_r1_stage2_quality_speed.sh` | 当前 P0 主入口，用来先跑通一次训练闭环 |
| Verl patch | 新增 `purpcode/script/patch_verl_pentest_multiturn.py` | repro 脚本会自动 apply；训练前仍需留意 patch 是否成功 |
| Baseline interaction | 新增 `purpcode/rl/pentest_r1_stage2_interaction_baseline.yaml` | baseline 使用，`judge_progress.enabled=false` |
| Quality-speed interaction | 新增 `purpcode/rl/pentest_r1_stage2_interaction_quality_speed.yaml` | 快速验证使用，`max_steps=2`、不要求 `</think>` |
| Judge 入口 | 最新 `repro.sh` 顶部强制 `PENTEST_R1_STAGE2_ENABLE_JUDGE_PROGRESS=0`，且默认 baseline config | 暂时后置；先不为 Judge 分散排障精力 |
| AutoPenBench 评测 | 仍使用 `script/run_autopenbench_full.sh` | 注意显式覆盖 `AUTOPENBENCH_MODEL_PATH`，否则会评测旧默认路径 |

## 1. 总原则

| 原则 | 说明 |
|---|---|
| 跑完训练优先于正式指标 | 目前还没有一次成功跑完训练，因此先降低训练复杂度，优先打通数据、patch、Ray、vLLM、rollout、checkpoint 与日志链路 |
| 当前主入口使用 quality-speed | `main_grpo_pentest_r1_stage2_quality_speed.sh` 是当前 P0，允许牺牲正式实验口径换取更短反馈周期 |
| 不把 speed 结果包装成论文主结果 | speed 默认 `max_steps=2`、`turn_max_new_tokens=128`、`max_interaction_tokens=512`，可作为工程跑通记录，不能直接替代正式 8 步实验 |
| 每次失败都要留下定位信息 | 失败时保留 `run_logs`、Ray 日志、`exit_status.txt`、GPU/磁盘快照和最后 200 行训练日志，避免重复盲跑 |
| Judge 暂时后置 | Judge 会引入 API、fallback、reward shaping、日志路径等额外变量；在 speed no-judge 训练成功前不要进入 Judge 排障 |
| 正式评测后置 | AutoPenBench 统一评测只在至少有一个可用 checkpoint 后执行，避免在训练未通时消耗评测时间 |

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

当前优先生成 quality-speed 数据：

```bash
bash script/build_pentest_r1_stage2_quality_speed_dataset.sh
```

repro 数据可在 speed 跑通后再生成：

```bash
conda run --no-capture-output -n purpcode python rl/data/pentest_r1_stage2.py \
  --root-dir ./local_data \
  --dataset-name pentest-r1-stage2-repro
```

完成标准：

| 数据集 | 用途 | 是否主结果 |
|---|---|---|
| `pentest-r1-stage2` | 旧 strict 主实验数据 | 可作为对照 |
| `pentest-r1-stage2-repro` | 最新 repro baseline 默认数据 | 后续正式实验使用 |
| `pentest-r1-stage2-quality-speed` | 当前 P0 训练跑通数据 | 当前优先 |
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

当前只把训练跑通作为目标，因此先跑 Stage2 与 rollout 相关测试；Judge 相关测试可以顺手跑，但不应阻塞 quality-speed no-judge 训练。

```bash
cd /home/ubuntu/RL/purpcode

conda run --no-capture-output -n purpcode python -m unittest \
  test/test_pentest_r1_stage2.py \
  test/test_pentest_r1_stage2_rollout_utils.py
```

可选：如果上述测试通过，再跑 Judge 与 wiring 检查，为后续方法线提前暴露问题：

```bash
conda run --no-capture-output -n purpcode python -m unittest \
  test/test_pentest_r1_stage2_judge.py
```

```bash
conda run --no-capture-output -n purpcode python script/check_pentest_r1_stage2_wiring.py
conda run --no-capture-output -n purpcode python script/test_pentest_r1_stage2_judge_integration.py
```

完成标准：

| 检查项 | 通过条件 |
|---|---|
| Stage2 单元测试 | prompt、Action 解析、dataset example 正常 |
| Judge 单元测试 | 可选；delta、cap、anti-repeat、fallback 正常 |
| Rollout utils 测试 | early stop、heredoc、submit、response window 正常 |
| Wiring check | 可选；fake episode 能产生 base reward 与 judge reward |

## 4. Phase 2：优先跑通 quality-speed 训练

目的：先完成一次从数据加载、rollout、reward、GRPO 更新、checkpoint 保存到日志落盘的完整训练闭环。当前阶段不要求它满足论文正式实验口径，也不要求立刻接入 Judge；只要求训练真实跑完并留下可复查产物。

第一次建议使用最保守配置，尽量减少单次反馈成本：

```bash
cd /home/ubuntu/RL/purpcode

CUDA_VISIBLE_DEVICES=0,1,2,3 \
PENTEST_R1_REPRO_STAGE2_MAX_EPOCHS=1 \
PENTEST_R1_REPRO_STAGE2_SAVE_FREQ=1 \
bash rl/main_grpo_pentest_r1_stage2_quality_speed.sh
```

完成标准：

| 产物或现象 | 路径或判断 |
|---|---|
| 正常退出 | `exit_status.txt` 中记录 `EXIT_CODE=0`，或终端退出码为 0 |
| checkpoint | `models/pentest-r1-stage2-quality-speed-*/global_step_*` |
| 训练日志 | `models/<experiment>/run_logs/<timestamp>/train.log` |
| 环境记录 | `env.txt`、`command.txt`、`exit_status.txt` |
| Ray 日志快照 | `run_logs/<timestamp>/ray_logs/`，如 Ray 目录存在 |
| 资源监控 | `resource_monitor.log`，如果启用 |
| 训练确实发生 | 日志中能看到 rollout、reward、advantage、loss、save checkpoint 等关键阶段 |

如果 quality-speed 仍失败，不要直接切 strict repro 或 Judge。先按下面顺序定位：

| 排查顺序 | 检查项 | 典型处理 |
|---:|---|---|
| 1 | `exit_status.txt` 和 `train.log` 最后 200 行 | 先确定是数据、容器、Ray、显存、vLLM 还是 checkpoint 保存问题 |
| 2 | `command.txt` | 确认实际参数是否真的是 quality-speed，而不是继承了旧环境变量 |
| 3 | `env.txt` | 检查 `CUDA_VISIBLE_DEVICES`、Conda 环境、模型路径、数据路径 |
| 4 | Ray 日志 | 查 actor 崩溃、worker timeout、对象存储溢出 |
| 5 | `nvidia-smi` / `df -h` | 查显存占用、旧进程、磁盘空间 |
| 6 | Docker 容器状态 | 查交互环境是否能启动、是否有 stale container 干扰 |

首次跑通后需要记录：

```text
experiment_name=<实际实验名>
script=rl/main_grpo_pentest_r1_stage2_quality_speed.sh
dataset=pentest-r1-stage2-quality-speed
judge_enabled=false
max_epochs=1
max_steps=2
turn_max_new_tokens=128
max_interaction_tokens=512
checkpoint=global_step_<N>
exit_code=0
耗时=<实际耗时>
主要瓶颈=<显存/容器/Ray/rollout/保存checkpoint/其他>
```

## 5. Phase 3：复跑 quality-speed 并收敛工程问题

首次成功只说明链路可以跑通，还不能说明训练稳定。第二步应在相同入口上复跑，目标是确认“不是偶然成功”，并根据第一次日志决定是否略微提高训练成本。

建议顺序：

| 顺序 | 操作 | 目的 |
|---:|---|---|
| 1 | 原参数复跑一次 `quality_speed` | 确认同配置能稳定完成 |
| 2 | 如果耗时可接受，将 `PENTEST_R1_REPRO_STAGE2_MAX_EPOCHS` 保持为 1，但保留完整日志 | 保持快速反馈，不急于扩大规模 |
| 3 | 如果失败，优先修复失败点，不要同时改多个参数 | 保持因果可解释 |
| 4 | 如果连续两次成功，再考虑切 strict repro | 进入正式实验线 |

复跑记录表：

```markdown
| Date | Experiment | Script | Dataset | Epochs | Exit | Checkpoint | Time | Failure / Note |
|---|---|---|---|---:|---:|---|---|---|
| 2026-xx-xx | quality-speed-1 | main_grpo_pentest_r1_stage2_quality_speed.sh | pentest-r1-stage2-quality-speed | 1 | 0 | global_step_<N> | TBD | first success |
| 2026-xx-xx | quality-speed-2 | main_grpo_pentest_r1_stage2_quality_speed.sh | pentest-r1-stage2-quality-speed | 1 | TBD | TBD | TBD | stability rerun |
```

## 6. Phase 4：speed 跑通后再做正式 no-judge baseline 复现

只有在 quality-speed 至少成功一次，最好连续成功两次后，再切换到 strict no-judge baseline。该阶段才服务于论文正式消融。

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

## 7. Phase 5：恢复或新增 strict judge repro 入口

最新 `main_grpo_pentest_r1_stage2_repro.sh` 顶部有：

```bash
export PENTEST_R1_STAGE2_ENABLE_JUDGE_PROGRESS=0
```

并且默认使用：

```bash
INTERACTION_CONFIG=./rl/pentest_r1_stage2_interaction_baseline.yaml
```

因此，正式 Judge 实验前必须做一个明确改动。注意：该任务当前后置，不应阻塞 quality-speed 跑通。建议新增文件，不直接破坏 baseline：

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

## 8. Phase 6：正式 strict judge 训练

该阶段必须在以下条件全部满足后再开始：

| 前置条件 | 要求 |
|---|---|
| quality-speed | 至少 1 次成功，建议 2 次成功 |
| strict no-judge repro | 至少 1 次成功，拿到可用 checkpoint |
| Judge wrapper | 已验证不会被 `repro.sh` 内部变量覆盖 |
| API | `DASHSCOPE_API_KEY` 可用，且 fallback rate 可控 |

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

## 9. Phase 7：统一 AutoPenBench 评测

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

## 10. Phase 8：结果登记与对比

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
| 2026-xx-xx | Quality-speed run-through | main_grpo_pentest_r1_stage2_quality_speed.sh | pentest-r1-stage2-quality-speed | no | global_step_<N> | none | n/a | n/a | n/a |
```

## 11. Phase 9：补充两个分析脚本

### 11.1 Judge 日志分析脚本

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

### 11.2 AutoPenBench 逐任务对比脚本

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

## 12. 后续消融优先级

当前先跑通训练，不要在 quality-speed 成功前做正式消融。训练链路稳定后，再按下面优先级推进。

| 优先级 | 消融 | 实现方式 | 目的 |
|---|---|---|---|
| P0 | quality-speed no-judge | `main_grpo_pentest_r1_stage2_quality_speed.sh` | 当前第一目标：跑完训练闭环 |
| P0 | quality-speed rerun | 同一脚本同一数据复跑 | 验证训练稳定性 |
| P1 | no-judge repro | 最新 `main_grpo_pentest_r1_stage2_repro.sh` | 正式 baseline |
| P1 | judge repro | 新增 `main_grpo_pentest_r1_stage2_repro_judge.sh` | 正式方法 |
| P1 | no negative flags | 将 `repetitive/stalling/hallucinated` penalty 设为 0 | 验证负向 Judge 标记作用 |
| P1 | no cap | 提高或关闭 `judge_total_bonus_cap` | 验证 cap 防止 reward overpower |
| P1 | different frequency | `evaluate_every_n_steps=1/4` | 评估成本与效果折中 |
| P2 | heuristic progress reward | 用规则奖励新文件、新 URL、新 artifact | 对比 LLM Judge 与规则 shaping |
| P2 | random judge | 随机或打乱 judge score | 排除“多一个 reward”本身的解释 |

## 13. 目前最应该立刻做的 12 件事

| 顺序 | 任务 | 完成标志 |
|---:|---|---|
| 1 | 在训练服务器确认 Stage1 merged model 存在 | `config.json`、tokenizer 文件可见 |
| 2 | 生成 `pentest-r1-stage2-quality-speed` 数据集 | `local_data/pentest-r1-stage2-quality-speed/train.parquet` 存在 |
| 3 | 跑 Stage2 与 rollout utils 相关 unittest | Stage2、rollout utils 通过；Judge 测试可跑但不阻塞 speed |
| 4 | 检查 Docker、Ray、GPU、磁盘 | 训练前环境可用，无明显旧进程和空间风险 |
| 5 | 跑第一次 quality-speed 训练 | `EXIT_CODE=0`、checkpoint 和 run_logs 存在 |
| 6 | 如果失败，整理失败日志并只修一个主因 | 有明确失败原因和下一次改动 |
| 7 | 复跑 quality-speed | 同入口第二次成功，或定位出稳定性问题 |
| 8 | 记录 quality-speed 实验表 | 实验名、参数、checkpoint、耗时、失败点齐全 |
| 9 | 生成 `pentest-r1-stage2-repro` 数据集 | `local_data/pentest-r1-stage2-repro/train.parquet` 存在 |
| 10 | 跑 strict no-judge repro | `global_step_<N>/actor/huggingface` 存在 |
| 11 | 新增 judge repro wrapper 和 judge yaml | baseline 不变，judge wrapper 可启用 Judge |
| 12 | 跑 strict judge repro 与后续 AutoPenBench | checkpoint、judge logs、评测结果齐全 |

## 14. 常见坑位

| 坑位 | 后果 | 规避 |
|---|---|---|
| 一上来跑 strict repro 或 Judge | 失败反馈周期长，难以定位是训练链路问题还是方法问题 | 当前先跑 `main_grpo_pentest_r1_stage2_quality_speed.sh` |
| 继续只用旧 `main_grpo_pentest_r1_stage2.sh` | 错过最新日志、patch、preflight 和稳定性改动 | 当前 speed 用 `main_grpo_pentest_r1_stage2_quality_speed.sh`，正式 baseline 再用 `main_grpo_pentest_r1_stage2_repro.sh` |
| 误把 quality-speed 当论文主结果 | `max_steps=2` 等设置与正式实验不一致 | 只作为当前跑通与工程稳定性记录 |
| 每次失败后同时改多个参数 | 下次成功或失败都无法归因 | 每轮只改一个主因，并记录在实验表 |
| wrapper 设置 Judge 但被 repro 脚本覆盖为 0 | 实际仍是 no-judge | 修改 repro 脚本，使 enable 变量可配置 |
| 忘记生成 `pentest-r1-stage2-repro` | repro 脚本找不到默认数据 | 先运行数据生成命令 |
| 忘记生成 `pentest-r1-stage2-quality-speed` | speed 脚本找不到默认数据 | 当前阶段优先生成 quality-speed 数据 |
| 忘记覆盖 `AUTOPENBENCH_MODEL_PATH` | 评测旧默认 checkpoint | 每次评测前显式设置并登记 |
| scenario `exit_code=1` | aggregate 结果不完整 | 必须检查所有 `exit_code.txt` |
| Judge API key 为空 | Judge fallback，方法无效 | Judge 阶段再检查；当前 speed 阶段不应被它阻塞 |
| 磁盘不足 | repro preflight 直接失败 | 提前检查 150GB 空间或改输出目录 |
| GPU 被旧进程占用 | GPU preflight 失败或训练不稳定 | 用 `nvidia-smi` 清理旧 Ray/vLLM/训练进程 |

## 15. 当前阶段交付物

当前“先跑通训练”阶段结束时，至少应形成：

```text
purpcode/models/<quality_speed_experiment>/global_step_<N>/
purpcode/models/<quality_speed_experiment>/run_logs/<timestamp>/train.log
purpcode/models/<quality_speed_experiment>/run_logs/<timestamp>/env.txt
purpcode/models/<quality_speed_experiment>/run_logs/<timestamp>/command.txt
purpcode/models/<quality_speed_experiment>/run_logs/<timestamp>/exit_status.txt
purpcode/models/<quality_speed_experiment>/run_logs/<timestamp>/resource_monitor.log
purpcode/eval_results/EXPERIMENT_REGISTRY.md 或等价实验记录表
```

后续正式论文实验阶段再补齐：

```text
purpcode/models/<nojudge_repro_experiment>/global_step_<N>/actor/huggingface/
purpcode/models/<judge_repro_experiment>/global_step_<N>/actor/huggingface/
purpcode/models/<nojudge_repro_experiment>/run_logs/<timestamp>/
purpcode/models/<judge_repro_experiment>/run_logs/<timestamp>/
purpcode/eval_results/autopenbench_repro_nojudge_step<N>/aggregate_summary.json
purpcode/eval_results/autopenbench_repro_judge_step<N>/aggregate_summary.json
purpcode/eval_results/EXPERIMENT_REGISTRY.md
purpcode/eval_results/compare_repro_nojudge_vs_judge_step<N>.md
purpcode/logs/judge_progress_summary.json
purpcode/logs/judge_progress_summary.md
```

判断是否可以从当前阶段进入正式阶段的标准很简单：`quality-speed` 至少成功跑完一次，最好连续两次成功，并且失败/成功日志都能解释。如果这个标准还没有满足，就继续围绕 speed 入口排障，不要提前切 Judge 或完整复现。
