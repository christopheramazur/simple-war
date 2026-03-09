# Main Concepts — Entity & Activity Relationships

Diagrams derived from **Main Concepts**. Entities are the things; activities are what happens and how they connect.

---

## 1. Entities and relationships

```mermaid
erDiagram
    PLAYER ||--o{ ARMY : "fields"
    PLAYER ||--o{ ROSTER : "owns"
    PLAYER }o--o{ BATTLE : "participates in"
    PLAYER }o--o{ CAMPAIGN : "participates in"

    ROSTER ||--o{ ARMY : "lists"
    ROSTER {
        list of armies
        optional build restrictions
    }

    ARMY ||--o{ UNIT : "contains"
    ARMY {
        army list
        army value
    }

    BATTLE }o--|| BATTLEFIELD : "fought on"
    BATTLE }o--o{ ARMY : "opposing"
    BATTLE }o--|| CAMPAIGN : "part of"

    CAMPAIGN {
        opening
        activities
        conclusion
    }

    BATTLEFIELD {
        single per battle
    }
```

- **Players** field **Armies** and fight **Battles**. Armies live in a **Roster**; battles happen on a **Battlefield**. Together these form a **Campaign**.
- **Roster**: list of armies; may impose build restrictions (default: none).
- **Army**: built from **Units** (army list), has an army value; two opposing armies of similar value fight on one battlefield until one is wiped out.

---

## 2. Campaign structure (activities and flow)

A **Campaign** is how gameplay is organized: opening → participating in activities → conclusion.

```mermaid
flowchart LR
    subgraph OPENING["Opening"]
        A[Determine terms]
        B[Number & composition of activities]
        C[Objectives]
        A --> B --> C
    end

    subgraph PARTICIPATING["Participating"]
        D[Build army]
        E[Fight battle]
        D --> E
    end

    subgraph CONCLUSION["Conclusion"]
        F[Determine victor]
    end

    OPENING --> PARTICIPATING --> CONCLUSION
```

- **Opening**: terms of the campaign, number/composition of activities, objectives.
- **Participating**: e.g. each player builds an army, then they fight a battle.
- **Conclusion**: determine the victor. Campaigns can add, remove, or modify these activities.

---

## 3. Battle stages

Fighting a battle has four stages. Campaign or army rules can add steps or modify how each stage works.

```mermaid
flowchart LR
    subgraph PLANNING["Planning"]
        P[Select army from roster]
    end

    subgraph DEPLOYMENT["Deployment"]
        D[Deploy armies to battlefield]
    end

    subgraph ENGAGEMENT["Engagement"]
        E[Command armies]
        T[Turns: repeating cycle of phases]
        E --> T
    end

    subgraph CONSOLIDATION["Consolidation"]
        C[Determine victor]
    end

    PLANNING --> DEPLOYMENT --> ENGAGEMENT --> CONSOLIDATION
```

- **Planning**: choose which army from the roster is used.
- **Deployment**: put that army on the battlefield.
- **Engagement**: command armies in **turns** (repeating phases) until one army is wiped out (or campaign rules say otherwise).
- **Consolidation**: decide who won. Campaign can change victory conditions, turn count, stage rules, or who can participate.

---

## 4. Where campaigns can modify battles

Campaigns sit above battles and can change how battles run.

```mermaid
flowchart TB
    CAMPAIGN["Campaign"]
    BATTLE["Battle (planning → deployment → engagement → consolidation)"]

    CAMPAIGN -->|"can enforce"| TURNS[Turn count]
    CAMPAIGN -->|"can add"| STAGE_RULES[Rules per stage]
    CAMPAIGN -->|"can add"| RESTRICT[Army participation restrictions]
    CAMPAIGN -->|"can change"| VICTORY[Victory conditions]

    TURNS --> BATTLE
    STAGE_RULES --> BATTLE
    RESTRICT --> BATTLE
    VICTORY --> BATTLE
```

---

## 5. One-page overview

```mermaid
flowchart TB
    subgraph WORLD["Simple War"]
        subgraph ENTITIES["Entities"]
            P[Players]
            RO[Rosters]
            A[Armies]
            U[Units]
            BF[Battlefield]
        end

        subgraph CAMPAIGN["Campaign"]
            O[Opening]
            ACT[Activities]
            CO[Conclusion]
            O --> ACT --> CO
        end

        subgraph BATTLE["Battle"]
            PL[Planning]
            DP[Deployment]
            EG[Engagement]
            CN[Consolidation]
            PL --> DP --> EG --> CN
        end
    end

    P -->|field| A
    P -->|own| RO
    RO -->|list| A
    A -->|contain| U
    P -->|participate in| CAMPAIGN
    P -->|participate in| BATTLE
    A -->|oppose in| BATTLE
    BATTLE -->|on| BF
    ACT -->|e.g.| BATTLE
    CAMPAIGN -->|modifies| BATTLE
```

---

*Source: Game Design Document — Overview / Main Concepts*
