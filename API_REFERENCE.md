# 🧩 Simploid API Reference

---

## ⚙️ Changable Attributes - (Are set by :SetAttribute)
| **Attribute** | **Type** | **Default Value** | **Description** |
|----------------|-----------|-------------------|-----------------|
| `Health` | `number` | `100` | The current health of the Simploid. |
| `MaxHealth` | `number` | `100` | The maximum health the Simploid can have. |
| `WalkSpeed` | `number` | `16` | Determines how fast the Simploid moves. |
| `RootHeight` | `number` | `3` | The vertical offset used to detect the ground from the HumanoidRootPart. |

---

## 📦 Server

### **Attributes**
| Name | Type | Description |
|------|------|--------------|
| `RayDownParams` | `RaycastParams` | Parameters used for downward raycasts (for character grounding). |

### **Methods**
| Method | Description |
|---------|--------------|
| `:SetAttribute(attributeName: string, attributeValue: any)` | Sets a custom attribute on the Simploid instance. |
| `:GetAttribute(attributeName: string) → any` | Returns the value of a stored attribute. |
| `:MoveTo(position: Vector3)` | Moves the Simploid to the given position using linear motion. |
| `:CancelMoveTo()` | Cancels the current movement operation. |
| `:PathfindTo(position: Vector3)` | Calculates and follows a path to the given position. |
| `:SetTimedPosition()` | Moves the Simploid based on a timed pattern. |
| `:Wander()` | Makes the Simploid move randomly around its current location. |
| `:Death()` | Handles death logic. |
| `:Destroy()` | Destroys the Simploid instance and cleans up memory. |


---

## 💻 Client

### **Attributes**
| Name | Type | Description |
|------|------|--------------|
| `RayDownParams` | `RaycastParams` | Parameters used for downward raycasts (for character grounding). |

### **Methods**
| Method | Description |
|---------|--------------|
| `:SetAttribute(attributeName: string, attributeValue: any)` | Sets a client-side attribute on the Simploid. |
| `:GetAttribute(attributeName: string) → any` | Retrieves a client-side attribute value. |
| `:LoadAnimation(animation: Animation) → AnimationTrack` | Loads and returns a playable animation track. |
| `:Death()` | Handles death visuals and effects on the client. |
| `:Destroy()` | Cleans up the Simploid’s client instance. |

