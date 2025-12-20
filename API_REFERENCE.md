# 🧩 Simploid API Reference

---

## ⚙️ Changable Attributes - (Are set by :SetAttribute)
| **Attribute** | **Type** | **Default Value** | **Description** |
|----------------|-----------|-------------------|-----------------|
| `Health` | `number` | `100` | The current health of the Simploid. |
| `MaxHealth` | `number` | `100` | The maximum health the Simploid can have. |
| `WalkSpeed` | `number` | `16` | Determines how fast the Simploid moves. |
| `JumpHeight` | `number` | `7.2` | Determines how high the Simploid jumps. |
| `RootHeight` | `number` | `3` | The vertical offset used to detect the ground from the HumanoidRootPart. |

---

## 🏃‍➡️ Simploid States
| **State Name(string)** | **Description** |
|------------------------|-----------------|
| `Idle` | Simploid is in normal state, doing nothing. | 
| `Running` | Constant linear moving state. |
| `Jumping` | Jump state. |
| `Falling` | Falling state when ground is far below. | 

---

## 📦 Server - (Changeable with the Simploid object itself, example : Simploid.RayDownParams = RaycastParams.new(...))

### **Properties**
| Name | Type | Description |
|------|------|--------------|
| `RayDownParams` | `RaycastParams` | Ray parameters object used for downward raycasts (for character grounding). |
| `Path` | `Path` |  Path object for built-in pathfinding. |

### **Methods**
| Method | Description |
|---------|--------------|
| `:SetAttribute(attributeName: string, attributeValue: any)` | Sets a custom attribute on the Simploid instance. |
| `:GetAttribute(attributeName: string) → any` | Returns the value of a stored attribute. |
| `:GetAttributeChangedSignal(attributeName: string) → RBXScriptSignal?` | Returns the signal connection of a stored attribute. |
| `:ReplicateProperty(attributeName: string, value: any)` | Replicates a property change from server to client. |
| `:MoveTo(position: Vector3)` | Moves the Simploid to the given position using linear motion. |
| `:CancelMoveTo()` | Cancels the current movement operation. |
| `:PathfindTo(position: Vector3)` | Calculates and follows a path to the given position. |
| `:SetTimedPosition()` | Updates the Simploid based on a timed pattern. |
| `:Jump()` | Makes the Simploid jump. |
| `:Wander()` | Makes the Simploid move randomly around its current location. |
| `:Death()` | Handles death logic. |
| `:Destroy()` | Destroys the Simploid instance and cleans up memory. |


---

## 💻 Client

### **Properties**
| Name | Type | Description |
|------|------|--------------|
| `RayDownParams` | `RaycastParams` | Parameters used for downward raycasts (for character grounding). |

### **Methods**
| Method | Description |
|---------|--------------|
| `:SetAttribute(attributeName: string, attributeValue: any)` | Sets a client-side attribute on the Simploid. |
| `:GetAttribute(attributeName: string) → any` | Retrieves a client-side attribute value. |
| `:GetAttributeChangedSignal(attributeName: string) → RBXScriptSignal?` | Returns the signal connection of a stored attribute. |
| `:LoadAnimation(animation: Animation) → AnimationTrack` | Loads and returns a playable animation track. |
| `:Death()` | Handles death visuals and effects on the client. |
| `:Destroy()` | Cleans up the Simploid’s client instance. |

