extends Node3D

@onready var lefthandleIK : SkeletonIK3D = $model/Skeleton3D/LeftHandleIK
@onready var weaponboneattachment : BoneAttachment3D = $model/Skeleton3D/WeaponBoneAttachment
@onready var tilt_pivot : Node3D = $model/Skeleton3D/WeaponBoneAttachment/TiltPivot
